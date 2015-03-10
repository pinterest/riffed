defmodule Rift.Struct do
  @moduledoc ~S"""
  Parse your thrift files and build some Elixir-y structs and conversions functions for you.

  Assuming you have the following Thrift strucs defined in src/request_types.erl:

        struct User {
          1: i32 id,
          2: string firstName,
          3: string lastName;
        }

        struct Request {
          1: User user,
          2: list<string> cookies,
          3: map<string, string> params;
        }


  You import them thusly:

    defmodule Request do
       use Rift.Struct, request_types: [:Request, :User]
    end

  Note that the use statment takes a keyword list whose names are thrift modules and whose values are
  the structs that you would like to import.

  Your request module now has User and Request submodules, and the top level module has conversion
  functions added to it so you can do the following:

        Request.to_elixir({:User, 32, "Steve", "Cohen"})
        > %Request.User{id: 32, firstName: "Steve", lastName: "Cohen"}

        user = Request.User.new(firstName: "Richard", lastName: "Feynman", id: 3221)
        > %Request.User{id: 3221, firstName: "Richard", lastName: "Feynman"}
        Request.to_erlang(user)
        > {:User, 3221, "Richard", "Feynman"}

  ### Note:
  Keys not set will have the initial value of :undefined.

  """
  defmodule StructData do
    defstruct struct_modules: [], tuple_converters: [], struct_converters: []

    def append(data=%StructData{}, struct_module, tuple_stanza, struct_function) do
      %StructData{struct_modules: [struct_module | data.struct_modules],
                  tuple_converters: [tuple_stanza | data.tuple_converters],
                  struct_converters: [struct_function | data.struct_converters]}
    end
  end

  defmacro __using__(opts) do
    quote do
      @thrift_options unquote(opts)
      @before_compile Rift.Struct
    end
  end

  defp build_struct_args(struct_meta) do
    Enum.map(struct_meta, fn({_, _, _, name, _}) -> {name, :undefined} end)
  end

  defp downcase_first(s) when is_bitstring(s) do
    <<first, rest :: binary>> = s
    String.downcase(List.to_string([first])) <> rest
  end

  defp downcase_first(a) when is_atom(a) do
    a
    |> Atom.to_string
    |> downcase_first
    |> String.to_atom
  end

  defp build_struct_and_conversion_function(struct_data=%StructData{}, container_module, struct_module_name, thrift_module)  do
    {:struct, meta} = :erlang.apply(thrift_module, :struct_info_ext, [struct_module_name])
    struct_args = build_struct_args(meta)
    fq_module_name = Module.concat([container_module, struct_module_name])
    record_name = downcase_first(struct_module_name)
    record_file = "src/#{thrift_module}.hrl"

    tuple_to_elixir = build_tuple_to_elixir(container_module, struct_module_name, fq_module_name, meta)
    struct_to_erlang = build_struct_to_erlang(fq_module_name, meta, record_name, struct_module_name)

    struct_module = quote do
      defmodule unquote(fq_module_name) do
        require Record

        Record.defrecord(unquote(record_name),
                         Record.extract(unquote(struct_module_name),
                                        from: unquote(record_file)))
        defstruct unquote(struct_args)

        def new(opts \\ unquote(struct_args)) do
          Enum.reduce(opts, %unquote(fq_module_name){}, fn({k, v}, s) -> Map.put(s, k, v) end)
        end
      end
    end

    StructData.append(struct_data, struct_module, tuple_to_elixir, struct_to_erlang)
  end

  defp build_tuple_to_elixir(container_module, thrift_name, module_name, meta) do
    # Builds a conversion function that take a tuple and converts it into an Elixir struct

    pos_args = [thrift_name] ++ Enum.map(meta, fn({_, _, _, name, _}) ->
                                           Macro.var(name, module_name) end)
    pos_args = {:{}, [], pos_args}
    keyword_args = Enum.map(
      meta, fn({_,_,_,name,_}) ->
        {name, {{:., [], [{:__aliases__, [], [container_module]}, :to_elixir]},
                [], [Macro.var(name, module_name)]}} end)

    quote do
      def to_elixir(unquote(pos_args)) do

        unquote(module_name).new(unquote(keyword_args))
      end

    end
  end

  defp build_struct_to_erlang(struct_module, meta, record_fn_name, record_name) do
    #  Builds a conversion function that turns an Elixir struct into an erlang record

    kwargs = Enum.map(meta, fn({_, _, _, name, _}) ->
                        {name, {{:., [], [{:s, [], Rift.Struct}, name]}, [], []}} end)
    quote do
      def to_erlang(s=%unquote(struct_module){}) do
        require unquote(struct_module)
        unquote(struct_module).unquote(record_fn_name)(unquote(kwargs))
        |> put_elem(0, unquote(record_name))
      end
    end
  end

  defmacro __before_compile__(env) do
    options = Module.get_attribute(env.module, :thrift_options)

    struct_data = Enum.reduce(
      options,
      %StructData{},
      fn({thrift_module, struct_names}, data) ->
        Enum.reduce(struct_names, data,
          fn(struct_name, data) ->
            build_struct_and_conversion_function(data, env.module, struct_name, thrift_module)
          end)
      end)

    quote do
      unquote_splicing(struct_data.struct_modules)
      unquote_splicing(struct_data.tuple_converters)

      def to_elixir({k, v}) do
        {to_elixir(k), to_elixir(v)}
      end

      def to_elixir(t) when is_tuple(t) do
        first = elem(t, 0)
        case first do
          :dict ->
            Enum.into(:dict.to_list(t), HashDict.new, &to_elixir/1)
          :set ->
            Enum.into(:sets.to_list(t), HashSet.new, &to_elixir/1)
          _ ->
            t
        end
      end

      def to_elixir(l) when is_list(l) do
        Enum.map(l, &to_elixir(&1))
      end

      def to_elixir(x) do
        x
      end

      unquote_splicing(struct_data.struct_converters)

      def to_erlang({k, v}) do
        {to_erlang(k), to_erlang(v)}
      end

      def to_erlang(l) when is_list(l) do
        Enum.map(l, &to_erlang(&1))
      end

      def to_erlang(d=%HashDict{}) do
        d
        |> Dict.to_list
        |> Enum.map(&to_erlang/1)
        |> :dict.from_list
      end

      def to_erlang(hs=%HashSet{}) do
        hs
        |> Set.to_list
        |> Enum.map(&to_erlang/1)
        |> :sets.from_list
      end

      def to_erlang(x) do
        x
      end
    end
  end

end
