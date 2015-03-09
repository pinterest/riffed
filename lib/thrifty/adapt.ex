defprotocol Thrifty.Adapt do
  @fallback_to_any true
    def to_elixir(_)
    def to_erlang(_)
end

defimpl Thrifty.Adapt, for: Any do
  def to_elixir(any) do
    any
  end
  def to_erlang(any) do
    any
  end
end

defimpl Thrifty.Adapt, for: HashDict do
  def to_elixir(d) do
    d
  end

  def to_erlang(d) do
    d
    |> Dict.to_list
    |> Enum.map(fn({k, v}) ->
                  {Thrifty.Adapt.to_erlang(k), Thrifty.Adapt.to_erlang(v)}
                end)
    |> :dict.from_list
  end
end

defimpl Thrifty.Adapt, for: HashSet do
  def to_elixir(hs) do
    hs
  end

  def to_erlang(hs) do
    hs
    |> Set.to_list
    |> Enum.map(&Thrifty.Adapt.to_erlang/1)
    |>  :sets.from_list
  end
end

defimpl Thrifty.Adapt, for: List do
  def to_elixir(l) do
    Enum.map(l, &Thrifty.Adapt.to_elixir(&1))
  end

  def to_erlang(l) do
    Enum.map(l, &Thrifty.Adapt.to_erlang(&1))
  end
end
