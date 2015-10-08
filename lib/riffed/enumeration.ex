defmodule Riffed.Enumeration do
  @moduledoc """
  Provides enumeration semantics, but with an Elixir flavor.

  ## Usage

  Thrift enums are not handled well by the erlang thrift bindings. They're turned into
  ints and left to fend for themselves. This is no way to treat an Enum. The `Riffed.Enum`
  module brings them back into the fold so you can have familiar enumeration semantics.

  To (re)define an enum, use the defenum macro like this:

      defenum UserState do
        :active -> 1
        :inactive -> 2
        :banned -> 3
      end

  Then, for all structs that use the enum, use the corresponding `enumerize_struct` macro:

      enumerize_struct(User, state: UserState)

  Riffed will then change the state field into a UserState enum whenever it deserializes a User
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
    @moduledoc false
    defstruct conversion_fns: [], modules: [], fn_args_conversions: HashDict.new
  end

  defmodule ArgConversion do
    @moduledoc false
    defstruct args: nil, return_type: nil, fn_name: nil

    def new(call, return_type) do
      {fn_name, args} = Macro.decompose_call(call)
      %ArgConversion{fn_name: fn_name, args: args, return_type: return_type}
    end
  end

  defmacro __using__(_opts) do
    Module.register_attribute(__CALLER__.module, :enums, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enums_orig, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_conversions, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_conversions_orig, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_arg_conversion, accumulate: true)
    Module.register_attribute(__CALLER__.module, :enum_arg_conversion_orig, accumulate: true)
    quote do
      require Riffed.Enumeration
      import Riffed.Enumeration, only: [defenum: 2,
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
    Module.put_attribute(__CALLER__.module, :enums_orig, {enum_name, mappings})
  end

  @doc """
  Tells Riffed that a struct has enums that need to be converted.
  Assume you have a struct that represents a user and they have a field named
  state that is a UserState enum.

      enumerize_struct(Structs.MyStruct, state: UserState)
  """
  defmacro enumerize_struct(struct_name, fields) do
    Module.put_attribute(__CALLER__.module, :enum_conversions, {struct_name, fields})
    Module.put_attribute(__CALLER__.module, :enum_conversions_orig, {struct_name, fields})
  end

  @doc """
  Tells Riffed to convert argument of the named function.
  The `fn_call` argument is a function signature to match, and you mark arguments to
  be converted to enums. For example:

      enumerize_function my_thrift_function(_, _, EnumOne, EnumTwo)
  """
  defmacro enumerize_function(fn_call) do
    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion,
                         ArgConversion.new(fn_call, nil))
    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion_orig, {fn_call, nil})
  end

  @doc """
  Tells Riffed to convert both arguments and return values of the named function to a struct.
  The `fn_call` argument is a function signature to match, and you mark arguments to be
  converted into enums. You can also provide a `returns:` keyword to mark the return value of
  the function to be converted into an enum. For example:

      enumerize_function get_enumeration(), returns: MyDefinedEnum
  """
  defmacro enumerize_function(fn_call, return_kwargs) do
    {return_type, _} = Code.eval_quoted(return_kwargs)

    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion,
                         ArgConversion.new(fn_call, return_type[:returns]))
    Module.put_attribute(__CALLER__.module,
                         :enum_arg_conversion_orig, {fn_call, return_kwargs})
  end

  @doc false
  def reconstitute(parent_module) do
    enum_declarations = Module.get_attribute(parent_module, :enums_orig)
    |> Enum.map(fn({enum_name, mapping_kwargs}) ->
                  quote do
                    defenum(unquote(enum_name), do: unquote(List.flatten(mapping_kwargs)))
                  end
                end)

    conversion_declarations = Module.get_attribute(parent_module, :enum_conversions_orig)
    |> Enum.map(fn({struct_name, field_name}) ->
                  quote do
                    enumerize_struct(unquote(struct_name), unquote(field_name))
                  end
                end)

    List.flatten([enum_declarations, conversion_declarations])
  end

  @doc false
  def build_cast_return_value_to_erlang(struct_module) do
    get_overrides(struct_module).functions
    |> Enum.reduce(
        [],
        fn({_fn_name, conversion=%ArgConversion{}}, acc) ->
          Enum.reduce(
            conversion.args, acc,
            fn
            ({_arg_name, :none}, acc) ->
              acc
            ({_arg_name, conversion}, acc) ->
              quoted = process_arg(struct_module, conversion)
              [quoted | acc]
            end)
        end)
  end

  @doc false
  def get_overridden_type(fn_name, :return_type, overrides, type_spec) do
    fn_overrides = Map.get(overrides, fn_name)
    if fn_overrides do
      fn_overrides.return_type || type_spec
    else
      type_spec
    end
  end

  def get_overridden_type(fn_name, arg_name, overrides, type_spec) do
    fn_overrides = Map.get(overrides, fn_name)

    if fn_overrides do
      case Keyword.get(fn_overrides.args, arg_name) do
        :none -> type_spec
        other -> other
      end
    else
      type_spec
    end
  end

  defp process_arg(struct_module, conversion) do
    enum_module = Module.concat(struct_module, conversion)
    quote do
      def to_erlang(enum=%unquote(enum_module){}, _) do
        enum.value()
      end
    end
  end

  @doc false
  def get_overrides(container_module) do
    {enum_field_conversions, _} = container_module
    |> Module.get_attribute(:enum_conversions)
    |> Code.eval_quoted

    enum_function_conversions = container_module
    |> Module.get_attribute(:enum_arg_conversion)
    |> Enum.map(fn(conv=%ArgConversion{}) ->
                  args = conv.args
                  |> Enum.with_index
                  |> Enum.map(fn
                              ({{_, _, nil}, idx}) ->
                                # underscore case ( enumerize_function my_fn(_) )
                                {:"arg_#{idx + 1}", :none}
                              ({other, idx}) ->
                                {rv_type, _} = Code.eval_quoted(other)
                                {:"arg_#{idx + 1}", rv_type}
                              end)
                  %ArgConversion{conv | args: args}
                end)
    structs = enum_field_conversions
    |> Enum.reduce(%{}, fn({struct_name, mappings}, acc) ->
                     fq_struct_name = Module.concat(:Elixir, Module.concat(container_module, struct_name))
                     Map.put(acc, fq_struct_name, mappings)
                   end)
    functions = enum_function_conversions
    |> Enum.reduce(%{}, fn(conversion, acc) ->
                     Map.put(acc, conversion.fn_name, conversion)
                   end)

    %{structs: structs, functions: functions}

  end

  @doc false
  def build(container_module) do
    enums = Module.get_attribute(container_module, :enums)
    enum_modules = Enum.map(enums, &build_enum_module/1)
    int_to_enums = Enum.map(enums,
                            &(build_erlang_to_enum_function(container_module, &1)))
    enum_to_ints = Enum.map(enums,
                            &(build_enum_to_erlang_function(container_module, &1)))

    enum_conversion_fns = Enum.concat(int_to_enums, enum_to_ints)

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

        def ordinals do
          unquote(Keyword.keys mapping)
        end

        def values do
          unquote(Keyword.values mapping)
        end

        def mappings do
          unquote(mapping)
        end
      end
    end
  end

  defp build_enum_to_erlang_function(container_module, enum_decl) do
    {{_, _, [enum_name]}, _} = enum_decl

    enum_alias = {:__aliases__, [alias: false], [enum_name]}
    fq_enum_name = Module.concat(container_module, enum_name)
    quote do
      def to_erlang(enum=%unquote(fq_enum_name){}, unquote(enum_alias)) do
        enum.value()
      end

      def to_erlang(enum=%unquote(fq_enum_name){}, _) do
        enum.value()
      end
    end
  end

  defp build_erlang_to_enum_function(container_module, enum_decl) do
    {{_, _, [enum_name]}, _} = enum_decl

    enum_alias = {:__aliases__, [alias: false], [enum_name]}
    fq_enum_name = Module.concat(container_module, enum_name)
    quote do
      def to_elixir(erlang_value, unquote(enum_alias)) do
        unquote(fq_enum_name).value(erlang_value)
      end
    end
  end
end
