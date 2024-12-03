defmodule Anoma.Node.Examples.ESolver do
  @moduledoc """
  I contain several examples on how to use the solver.
  """

  require ExUnit.Assertions
  import ExUnit.Assertions

  alias Anoma.Node.Event
  alias Anoma.Node.Intents.IntentPool
  alias Anoma.Node.Intents.Solver
  alias Anoma.RM.DumbIntent
  alias Anoma.Node.Examples.ENode

  use EventBroker.WithSubscription

  ############################################################
  #                           Scenarios                      #
  ############################################################

  @doc """
  I create a single transaction and ask the solver to solve it.
  The transaction cannot be solved, so it should be in the unbalanced list
  when the solver returns.
  """
  @spec solve_transaction() :: boolean()
  def solve_transaction() do
    # create an empty intent
    intent = %DumbIntent{}

    # solve the transaction
    assert Solver.solve([intent]) == MapSet.new([intent])
  end

  @doc """
  I solve multiple intents that are valid when composed.
  """
  @spec solve_transactions() :: boolean()
  def solve_transactions() do
    # create an empty intent
    intent_1 = %DumbIntent{value: -1}
    intent_2 = %DumbIntent{value: 1}

    # solve the transaction
    expected = Enum.sort([intent_1, intent_2])
    result = Enum.sort(Solver.solve([intent_1, intent_2]))
    assert expected == result
  end

  @doc """
  I solve multiple intents that are valid when composed.
  """
  @spec solve_transactions_with_remainder() :: boolean()
  def solve_transactions_with_remainder() do
    # create an empty intent
    intent_1 = %DumbIntent{value: -1}
    intent_2 = %DumbIntent{value: 1}
    intent_3 = %DumbIntent{value: 100}

    # solve the intents. only the first two can be solved.
    assert Enum.sort(Solver.solve([intent_1, intent_2, intent_3])) ==
             Enum.sort([intent_1, intent_2])
  end

  @doc """
  I insert a single transaction into the solver, which it cannot solve.
  I verify that the transaction is then in the unsolved list.
  """
  @spec solvable_transaction_via_intent_pool(ENode.t()) :: boolean()
  def solvable_transaction_via_intent_pool(enode \\ ENode.start_node()) do
    # startup
    # the solver does not have solved transactions.
    assert [] == Solver.get_solved(enode.node_id)
    assert [] == Solver.get_unsolved(enode.node_id)

    with_subscription [[Event.node_filter(enode.node_id)]] do
      # add an intent to the pool
      # note: this is asynchronous, so block this process for a bit
      intent_1 = %DumbIntent{value: -1}
      IntentPool.new_intent(enode.node_id, intent_1)

      :ok = wait_for_unsolved_intent_added(enode.node_id, intent_1)

      # the solver does not have solved transactions.
      assert Solver.get_solved(enode.node_id) == []
      assert Solver.get_unsolved(enode.node_id) == [intent_1]

      # --------------------------------------------------------------------------
      # add a second intent to make it solvable

      intent_2 = %DumbIntent{value: 1}
      IntentPool.new_intent(enode.node_id, intent_2)

      :ok = wait_for_intent_solved(enode.node_id, intent_2)

      # the solver does not have solved transactions.
      assert Solver.get_solved(enode.node_id) == [intent_1, intent_2]
      assert Solver.get_unsolved(enode.node_id) == []

      # --------------------------------------------------------------------------
      # add a third intent to make it unsolvable

      intent_3 = %DumbIntent{value: 1000}
      IntentPool.new_intent(enode.node_id, intent_3)

      :ok = wait_for_unsolved_intent_added(enode.node_id, intent_3)

      # the solver does not have solved transactions.
      assert Solver.get_solved(enode.node_id) == [intent_1, intent_2]
      assert Solver.get_unsolved(enode.node_id) == [intent_3]
    end
  end

  @doc """
  I test the behavior of separate solver instances across two different nodes.
  Each node manages its own intents and solves them independently.
  """
  @spec solvers_isolated() :: boolean()
  def solvers_isolated() do
    enode1 = ENode.start_node()
    enode2 = ENode.start_node()

    with_subscription [
      [Event.node_filter(enode1.node_id)],
      [Event.node_filter(enode2.node_id)]
    ] do
      intent_1 = %DumbIntent{value: -111}
      IntentPool.new_intent(enode1.node_id, intent_1)

      :ok = wait_for_unsolved_intent_added(enode1.node_id, intent_1)

      assert Solver.get_solved(enode1.node_id) == []
      assert Solver.get_unsolved(enode1.node_id) == [intent_1]
      assert Solver.get_solved(enode2.node_id) == []
      assert Solver.get_unsolved(enode2.node_id) == []

      intent_2 = %DumbIntent{value: -222}
      IntentPool.new_intent(enode2.node_id, intent_2)

      :ok = wait_for_unsolved_intent_added(enode2.node_id, intent_2)

      assert Solver.get_solved(enode1.node_id) == []
      assert Solver.get_unsolved(enode1.node_id) == [intent_1]
      assert Solver.get_solved(enode2.node_id) == []
      assert Solver.get_unsolved(enode2.node_id) == [intent_2]

      intent_3 = %DumbIntent{value: 111}
      IntentPool.new_intent(enode1.node_id, intent_3)

      :ok = wait_for_intent_solved(enode1.node_id, intent_1)

      assert Solver.get_solved(enode1.node_id) == [intent_1, intent_3]
      assert Solver.get_unsolved(enode1.node_id) == []
      assert Solver.get_solved(enode2.node_id) == []
      assert Solver.get_unsolved(enode2.node_id) == [intent_2]

      intent_4 = %DumbIntent{value: 222}
      IntentPool.new_intent(enode2.node_id, intent_4)

      :ok = wait_for_intent_solved(enode2.node_id, intent_2)

      assert Solver.get_solved(enode1.node_id) == [intent_1, intent_3]
      assert Solver.get_unsolved(enode1.node_id) == []
      assert Solver.get_solved(enode2.node_id) == [intent_2, intent_4]
      assert Solver.get_unsolved(enode2.node_id) == []
    end
  end

  defp wait_for_intent_solved(node_id, intent) do
    receive do
      %EventBroker.Event{
        body: %Anoma.Node.Event{
          body: {:intent_solved, ^intent},
          node_id: ^node_id
        }
      } ->
        :ok
    after
      1000 -> {:error, :timeout}
    end
  end

  defp wait_for_unsolved_intent_added(node_id, intent) do
    receive do
      %EventBroker.Event{
        body: %Anoma.Node.Event{
          body: {:unsolved_intent_added, ^intent},
          node_id: ^node_id
        }
      } ->
        :ok
    after
      1000 -> {:error, :timeout}
    end
  end
end
