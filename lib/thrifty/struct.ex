defmodule Thrifty.Struct do
  defmodule StructData do
    defstruct struct_modules: [], tuple_stanzas: [], struct_protocols: []
    def append(data=%StructData{}, struct_module, tuple_stanza, struct_protocol) do
      %StructData{struct_modules: [struct_module | data.struct_modules],
                  tuple_stanzas: [tuple_stanza | data.tuple_stanzas],
                  struct_protocols: [struct_protocol | data.struct_protocols]}
    end
  end

  defmacro __using__(opts) do
    quote do
      @thrift_options unquote(opts)
      @before_compile Thrifty.Struct
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

  defp build_struct_and_protocol(struct_data=%StructData{}, container_module, struct_module_name, thrift_module)  do
    {:struct, meta} = :erlang.apply(thrift_module, :struct_info_ext, [struct_module_name])
    struct_args = build_struct_args(meta)
    fq_module_name = Module.concat([container_module, struct_module_name])
    record_name = downcase_first(struct_module_name)
    record_file = "src/#{thrift_module}.hrl"

    tuple_stanza = build_tuple_stanza(struct_module_name, fq_module_name, meta)
    struct_protocol = build_struct_protocol(fq_module_name, meta, record_name, struct_module_name)

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

    StructData.append(struct_data, struct_module, tuple_stanza, struct_protocol)
  end

  defp build_tuple_stanza(thrift_name, module_name, meta) do

    pos_args = [thrift_name] ++ Enum.map(meta, fn({_, _, _, name, _}) -> {name, [], module_name} end)
    pos_args = {:{}, [], pos_args}
    keyword_args = Enum.map(meta, fn({_,_,_,name,_}) -> {name, {{:., [], [{:__aliases__, [alias: false], [:Thrifty, :Adapt]}, :to_elixir]}, [], [{name, [], module_name}]}} end)

    quote do
      def to_elixir(unquote(pos_args)) do
        unquote(module_name).new(unquote(keyword_args))
      end

    end
  end

  defp build_struct_protocol(struct_module, meta, record_fn_name, record_name) do
    kwargs = Enum.map(meta, fn({_, _, _, name, _}) ->
                        {name, {{:., [], [{:s, [], Thrifty.Struct}, name]}, [], []}} end)
    quote do
      defimpl Thrifty.Adapt, for: unquote(struct_module) do
        require unquote(struct_module)
        def to_erlang(s) do
          unquote(struct_module).unquote(record_fn_name)(unquote(kwargs))
          |> put_elem(0, unquote(record_name))
        end

        def to_elixir(s=%unquote(struct_module){}) do
          s
        end
      end
    end
  end

  defp build_tuple_protocol(tuple_stanzas) do
    quote do
      defimpl Thrifty.Adapt, for: Tuple do
        def to_erlang(t) do
          t
        end

        unquote_splicing(tuple_stanzas)
        def to_elixir(t) do
          first = elem(t, 0)
          case first do
            :dict ->
              Enum.into(:dict.to_list(t), HashDict.new,
                        fn({k, v}) ->
                          {Thrifty.Adapt.to_elixir(k), Thrifty.Adapt.to_elixir(v)}
                        end)
            :set ->
              Enum.into(:sets.to_list(t), HashSet.new, &Thrifty.Adapt.to_elixir/1)
            _ -> t
          end
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    IO.puts "It's open? #{Module.open?(Thrifty.TupleBuilder)}"
    options = Module.get_attribute(env.module, :thrift_options)

    struct_data = Enum.reduce(
      options,
      %StructData{},
      fn({thrift_module, struct_names}, data) ->
        Enum.reduce(struct_names, data,
                    fn(struct_name, data) ->
                      build_struct_and_protocol(data, env.module, struct_name, thrift_module)
                    end)
      end)

    tuple_protocol = build_tuple_protocol(struct_data.tuple_stanzas)
   x = quote do
      unquote_splicing(struct_data.struct_modules)
      unquote(tuple_protocol)
      unquote_splicing(struct_data.struct_protocols)
    end
   # x |> Macro.to_string |> IO.puts
   x
  end

end
