defmodule Rift.Enumeration do
  @moduledoc """
  Thrift enums are not handled well by the erlang thrift bindings. They're turned into
  ints and left to fend for themselves. This is no way to treat an Enum. The `Rift.Enum`
  module brings them back into the fold so you can have familiar enumeration semantics
  but with an Elixir flavor.

  To (re)define an enum, use the defenum macro like this:

      defenum UserState do
        :active -> 1
        :inactive -> 2
        :banned -> 3
      end

  Then, for all structs that use the enum, use the corresponding `enumerize_struct` macro:

      enumerize_struct(User, state: UserState)

  Rift will then change the state field into a UserState enum whenever it deserializes a User
  struct. Similarly, UserState enums will be serialized as ints.


  ### Using Enumerations
  Enums are just Elixir structs in a module that defines functions for turning ints into enums
  and enums into ints. All enum modules have `value` and `ordinal` functions; `value` converts  an integer into an Enumeration and `ordinal` converts an atom into an Enumeration.

  Like all structs, enums can be pattern matched against:

      def ban_user(%User{state: UserState.banned}) do
        {:error, :already_banned}
      end

      def ban_user(user=%User{}) do
        User.ban(user)
      end
  """

  defmodule Output do
    defstruct conversion_fns: [], modules: [], fn_args_conversions: HashDict.new
  end

  defmodule ArgConversion do
    defstruct args: nil, return_type: nil, fn_name: nil

    def new(call, return_type) do
      {fn_name, args} = Macro.decompose_call(call)
      %ArgConversion{fn_name: fn_name, args: args, return_type: return_type}
    end
  end

  defmacro __using__(_opts) do
    Module.register_attribute(__CALLER__.module, :enums, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_conversions, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_arg_conversion, accumulate: true)
    quote do
      require Rift.Enumeration
      import Rift.Enumeration, only: [defenum: 2,
                                      enumerize_struct: 2,
                                      enumerize_function: 1,
                                      enumerize_function: 2,
                                     ]
    end
  end

  @doc """
  Defines an enum. Enums are a series of mappings from atoms to an integer value.
  They are specified much like cases in a cond statment, like this:

      defenum ResponseStatus do
        :success -> 200
        :server_error -> 500
        :not_found -> 404
      end
  """
  defmacro defenum(enum_name, do: mappings) do
    mapping_kwargs = Enum.map(
      mappings,
      fn
      ({:->, _, [[k], v]}) when is_atom(k)  ->
        {k, v}
        (other) ->
        x = Macro.to_string(other)
        raise "#{x} is not in the form :key -> value"
      end)
    Module.put_attribute(__CALLER__.module, :enums, {enum_name, mapping_kwargs})
  end

  @doc """
  Tells Rift that a struct has enums that need to be converted.
  Assume you have a struct that represents a user and they have a field named
  state that is a UserState enum.

      enumerize_struct(Structs.MyStruct, state: UserState)
  """
  defmacro enumerize_struct(struct_name, fields) do
    Module.put_attribute(__CALLER__.module, :enum_conversions, {struct_name, fields})
  end

  @doc """
  Tells rift to convert argument of the named function.
  The `fn_call` argument is a function signature to match, and you mark arguments to
  be converted to enums. For example:

     enumerize_function my_thrift_function(_, _, EnumOne, EnumTwo)
  """
  defmacro enumerize_function(fn_call) do
    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion,
                         ArgConversion.new(fn_call, nil))
  end

  @doc """
  Tells rift to convert both arguments and return values of the named function to a struct.
  The `fn_call` argument is a function signature to match, and you mark arguments to be
  converted into enums. You can also provide a `returns:` keyword to mark the return value of
  the function to be converted into an enum. For example:

      enumerize_function get_enumeration(), returns: MyDefinedEnum
  """
  defmacro enumerize_function(fn_call, return_kwargs) do
    [returns: {_, _, [return_type]}] = return_kwargs
    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion,
                         ArgConversion.new(fn_call, return_type ))
  end

  def reconstitute(parent_module) do
    enum_declarations = Module.get_attribute(parent_module, :enums)
    |> Enum.map(fn({enum_name, mapping_kwargs}) ->
                  mapping = Enum.map(mapping_kwargs,
                    fn({k, v}) ->
                      quote do
                        unquote(k) -> unquote(v)
                      end
                    end)

                  quote do
                    defenum(unquote(enum_name), do: unquote(List.flatten(mapping)))

                  end
                end)

    conversion_declarations = Module.get_attribute(parent_module, :enum_conversions)
    |> Enum.map(fn({struct_name, field_name}) ->
                  quote do
                    enumerize_struct(unquote(struct_name), unquote(field_name))
                  end
                end)

    List.flatten([enum_declarations, conversion_declarations])
  end

  def build_function_casts(dest_module, struct_module, function_name, direction) do
    conversions = Module.get_attribute(dest_module, :enum_arg_conversion)
    |> Enum.map(fn(conversion=%ArgConversion{}) ->
                  {conversion.fn_name, conversion}
                end)
    |> Enum.into(Keyword.new)

    case conversions[function_name] do
      nil -> []
      conversion = %ArgConversion{} ->
          conversion.args
          |> Stream.with_index
          |> Stream.map(&(build_function_cast(struct_module, &1, direction)))
      |> Enum.filter(fn(e) -> ! is_nil(e) end)
    end
  end

  def build_cast_return_value_to_erlang(struct_module, server_module) do
    Module.get_attribute(server_module, :enum_arg_conversion)
    |> Stream.filter(&(&1.return_type != nil))
    |> Enum.map(
        fn(conversion=%ArgConversion{}) ->
          fq_enum_name = Module.concat(struct_module, conversion.return_type)
          quote do
            def cast_return_value_to_erlang(elixir_enum=%unquote(fq_enum_name){}, unquote(conversion.fn_name)) do
              elixir_enum.value
            end
          end
        end)
  end

  def build_cast_return_value_to_elixir(struct_module, client_module) do
    Module.get_attribute(client_module, :enum_arg_conversion)
    |> Stream.filter(&(&1.return_type != nil))
    |> Enum.map(
        fn(conversion=%ArgConversion{}) ->
          fq_enum = Module.concat(struct_module, conversion.return_type)
          quote do
            def cast_return_value_to_elixir(value, unquote(conversion.fn_name)) do
              unquote(fq_enum).value(value)
            end
          end
        end)
  end

  def generate_default_casts do
    quote do
      def cast_return_value_to_elixir(value, fn_name) do
        value
      end

      def cast_return_value_to_erlang(value, _) do
        value
      end
    end
  end

  def build(container_module) do
    enum_conversions = Module.get_attribute(container_module, :enum_conversions)
    enums = Module.get_attribute(container_module, :enums)
    enum_modules = Enum.map(enums, &build_enum_module/1)
    int_to_enums = Enum.map(enum_conversions,
                            &(build_erlang_to_enum_functions(&1)))
    enum_to_ints = Enum.map(enum_conversions,
                            &(build_enum_to_erlang(container_module, &1)))

    enum_conversion_fns = Enum.concat(int_to_enums, enum_to_ints)
    |> add_default_converters
    |> Enum.reverse

    %Output{conversion_fns: enum_conversion_fns, modules: enum_modules}
  end

  defp build_enum_module({enum_name, mappings}) do
    mapping = Macro.expand(mappings, __ENV__)
    fns = Enum.map(
      mapping,
      fn({k, v}) ->
        quote do
          def unquote(k)() do
            %unquote(enum_name){ordinal: unquote(k), value: unquote(v)}
          end
          def value(unquote(v)) do
            %unquote(enum_name){ordinal: unquote(k), value: unquote(v)}
          end
        end
      end)

    quote do
      defmodule unquote(enum_name) do
        defstruct ordinal: nil, value: nil
        unquote_splicing(fns)
      end
    end
  end

  defp build_enum_to_erlang(container_module, {enum_module, opts}) do
    {_, _, [enum_name]} = enum_module
    fq_enum_module = Module.concat(container_module, enum_name)
    kwargs = Enum.map(opts,
      fn({name, _enum_type}) ->
        var = Macro.var(name, fq_enum_module)
        quoted_call = quote do: enum.unquote(var).value
        {name, quoted_call}
      end)
    quote do
      def convert_enums_to_erlang(enum=%unquote(container_module).unquote(enum_module){}) do
        %unquote(container_module).unquote(enum_module){enum | unquote_splicing(kwargs)}
      end
    end
  end

  defp build_erlang_to_enum_functions({enum_module, opts}) do
    opts
    |> Enum.map(
        fn({enum_name, enum_type}) ->
          build_erlang_to_enum_function( enum_module, enum_name, enum_type)
        end)
    |> List.flatten
  end

  defp build_erlang_to_enum_function(enum_module, name, enum_type) do
    {_, _, [enum_name]} = enum_module

    quote do
      def convert_to_enum(unquote(enum_name), unquote(name), value) do
        unquote(enum_type).value(value)
      end
    end
  end

  defp add_default_converters(converters) do
    default_converter = quote do
      def convert_enums_to_erlang(x) do
        x
      end

      def convert_to_enum(record_name, field_name, field_value) do
        field_value
      end
    end
    [default_converter | converters]
  end

  defp build_function_cast(_enum_module, {{:__aliases__, _, [_struct_name]}, sequence}, :to_erlang) do
    variable = Macro.var(:"arg_#{sequence + 1}", nil)
    quote do
      unquote(variable) = unquote(variable).value()
    end
  end

  defp build_function_cast(enum_module, {{:__aliases__, _, [struct_name]}, sequence}, :to_elixir) do
    variable = Macro.var(:"arg_#{sequence + 1}", nil)
    fq_enum_name = Module.concat(enum_module, struct_name)
    quote do
      unquote(variable) = unquote(fq_enum_name).value(unquote(variable))
    end
  end

  defp build_function_cast(_, _, _) do
    nil
  end

end
