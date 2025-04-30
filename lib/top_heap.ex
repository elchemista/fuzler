defmodule Fuzler.TopHeap do
  @moduledoc false
  # min-heap limited to N elements

  @doc false
  @spec new(any()) :: {:gb_trees.tree(any(), any()), any()}
  def new(n), do: {:gb_trees.empty(), n}

  @doc false
  @spec push_top(any(), {:gb_trees.tree(any(), any()), any()}) ::
          {:gb_trees.tree(any(), any()), any()}
  def push_top(item = {_k, _v, score}, {heap, n}) do
    heap =
      if :gb_trees.size(heap) < n do
        :gb_trees.enter(score, item, heap)
      else
        case :gb_trees.smallest(heap) do
          {min_score, _} when score > min_score ->
            {_, _, heap} = :gb_trees.take_smallest(heap)
            :gb_trees.enter(score, item, heap)

          _ ->
            heap
        end
      end

    {heap, n}
  end

  @doc false
  @spec to_desc_list({:gb_trees.tree(any(), any()), any()}) :: [any()]
  def to_desc_list({heap, _n}) do
    heap |> :gb_trees.to_list() |> Enum.reverse() |> Enum.map(&elem(&1, 1))
  end
end
