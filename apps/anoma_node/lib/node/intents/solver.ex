defmodule Anoma.Node.Intents.Solver do
  @moduledoc """
  I am a strawman intent solver for testing purposes.

  ### Public API

  I have the following public functionality:

  - `get_solved/0`
  - `send/1`
  """

  use TypedStruct
  use GenServer

  alias __MODULE__
  alias Anoma.Node
  alias Node.Intents.IntentPool
  alias Node.Registry
  alias Anoma.RM.Intent
  alias EventBroker.Broker
  alias EventBroker.Event
  alias EventBroker.Filters

  require Logger
  require Node.Event

  ############################################################
  #                    State                                 #
  ############################################################

  typedstruct do
    @typedoc """
    I hold the state for the solver process.

    ### Fields
    - `:unsolved`        - The set of unsolved intents.
    - `:solved`          - The set of solved intents.
    """
    field(:unsolved, MapSet.t(Intent.t()), default: MapSet.new())
    field(:solved, MapSet.t(Intent.t()), default: MapSet.new())
    field(:node_id, String.t())
  end

  ############################################################
  #                    Genserver Helpers                     #
  ############################################################

  @doc """
  I create a new solver process .
  """
  @spec start_link([any()]) :: GenServer.on_start()
  def start_link(args) do
    name = Registry.via(args[:node_id], __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @doc """
  I return all the solved intents.
  """
  @spec get_solved(String.t()) :: [Intent.t()]
  def get_solved(node_id) do
    name = Registry.via(node_id, __MODULE__)
    GenServer.call(name, :get_solved)
  end

  @doc """
  I return all the unsolved intents.
  """
  @spec get_unsolved(String.t()) :: [Intent.t()]
  def get_unsolved(node_id) do
    name = Registry.via(node_id, __MODULE__)
    GenServer.call(name, :get_unsolved)
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  @impl true
  def init(args) do
    # set default values for the arguments
    args = Keyword.validate!(args, [:node_id])

    node_id = args[:node_id]

    # subscribe to all new intent pool messages
    subscribe_to_new_intents(node_id)

    # fetch the unsolved intents from the intent pool
    unsolved_intents =
      Enum.to_list(IntentPool.intents(node_id))

    state =
      %Solver{
        unsolved: MapSet.new(unsolved_intents),
        node_id: node_id
      }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_solved, _from, state) do
    {:reply, handle_get_solved(state), state}
  end

  @impl true
  def handle_call(:get_unsolved, _from, state) do
    {:reply, handle_get_unsolved(state), state}
  end

  @impl true
  def handle_info(event = %Event{}, state) do
    handle_event(event, state)
  end

  ############################################################
  #                  Genserver Implementation                #
  ############################################################

  # @doc """
  # I handle a new event coming from the event broker.
  # I am only interested in new intents.
  # """
  @spec handle_event(Event.t(), t()) ::
          {:noreply, t()} | {:noreply, t(), {:continue, any()}}
  defp handle_event(event = %Event{}, state) do
    case event do
      %Event{
        source_module: IntentPool,
        body: %Anoma.Node.Event{body: {:intent_added, intent}}
      } ->
        handle_new_intent(intent, state)

      _ ->
        Logger.warning("unexpected event in solver: #{inspect(event)}")
        {:noreply, state}
    end
  end

  # @doc """
  # I return a list of all solved intents.
  # """
  @spec handle_get_solved(t()) :: [Intent.t()]
  defp handle_get_solved(state) do
    Enum.to_list(state.solved)
  end

  # @doc """
  # I return a list of all unsolved intents.
  # """
  @spec handle_get_unsolved(t()) :: [Intent.t()]
  defp handle_get_unsolved(state) do
    Enum.to_list(state.unsolved)
  end

  # @doc """
  # I handle adding a new intent.
  # I add the intent to the list of unsolved intents, and then attempt to solve.
  # """
  @spec handle_new_intent(Intent.t(), t()) ::
          {:noreply, t()} | {:noreply, t(), {:continue, any()}}
  defp handle_new_intent(intent, state) do
    Logger.debug("solver received new intent: #{inspect(intent)}")
    unsolved? = intent in state.unsolved
    solved? = intent in state.solved

    if not unsolved? and not solved? do
      do_solve(state, intent)
    else
      Logger.debug(
        "ignoring intent; unsolved: #{unsolved?}, solved: #{solved?}"
      )

      {:noreply, state}
    end
  end

  ############################################################
  #                           Solver                         #
  ############################################################

  # @doc """
  # I try and solve the intents currently in my state.
  # If I can solve some of them, I add them to the solved pool.
  # """
  @spec do_solve(t(), Intent.t()) :: {:noreply, t(), {:continue, any()}}
  def do_solve(state, new_intent) do
    updated_unsolved = MapSet.put(state.unsolved, new_intent)

    {new_state, newly_solved} =
      case solve(updated_unsolved) do
        nil ->
          new_state = %{state | unsolved: updated_unsolved}
          newly_solved = MapSet.new()
          {new_state, newly_solved}

        solved_now ->
          new_solved = MapSet.union(state.solved, solved_now)
          new_unsolved = MapSet.difference(updated_unsolved, solved_now)
          new_state = %{state | solved: new_solved, unsolved: new_unsolved}

          # Determine newly solved intents
          newly_solved = MapSet.difference(new_solved, state.solved)
          {new_state, newly_solved}
      end

    {
      :noreply,
      new_state,
      {:continue, {:emit_events, newly_solved, new_intent}}
    }
  end

  @impl true
  def handle_continue({:emit_events, newly_solved, new_intent}, state) do
    # Emit events for all newly solved intents
    Enum.each(newly_solved, &emit_intent_solved(state.node_id, &1))

    # If the new intent is not among the newly solved, emit unsolved intent added
    unless MapSet.member?(newly_solved, new_intent) do
      emit_unsolved_intent_added(state.node_id, new_intent)
    end

    {:noreply, state}
  end

  defp emit_intent_solved(node_id, intent) do
    EventBroker.event(
      Node.Event.new_with_body(node_id, {:intent_solved, intent}),
      Broker
    )
  end

  defp emit_unsolved_intent_added(node_id, intent) do
    EventBroker.event(
      Node.Event.new_with_body(node_id, {:unsolved_intent_added, intent}),
      Broker
    )
  end

  # @doc """
  # Given a list of intents, I attempt to find a subset of them that can be composed
  # and verified.
  # I return a list of all intents that can be solved when composed.
  #
  # I assume that the composition of intents is associative and commutative.
  # """
  @spec solve([Intent.t()] | MapSet.t(Intent.t())) ::
          MapSet.t(Intent.t()) | nil
  def solve(intents) do
    intents
    |> Enum.to_list()
    |> subsets()
    |> Stream.drop_while(&(valid?(&1) != true))
    |> Stream.take(1)
    |> Enum.to_list()
    |> Enum.map(&MapSet.new/1)
    |> List.first()
  end

  @doc """
  I check if a list of intents is valid by composing them and verifying if they satisfy
  the Intent.valid? predicate.
  """
  @spec valid?([Intent.t()]) :: true | {:error, any()}
  def valid?([]), do: {:error, :error}

  def valid?(intents) do
    intents
    |> Enum.reduce(&Intent.compose/2)
    |> Intent.verify()
  end

  ############################################################
  #                           Helpers                        #
  ############################################################

  # @doc """
  # I subscribe this process to the intent pool events.
  # """
  @spec subscribe_to_new_intents(String.t()) :: :ok | String.t()
  defp subscribe_to_new_intents(node_id) do
    filter = %Filters.SourceModule{module: IntentPool}

    EventBroker.subscribe_me([
      Node.Event.node_filter(node_id),
      filter
    ])
  end

  @doc """
  I generate all possible subsets of a given list of elements as a stream.
  """
  @spec subsets(Enumerable.t()) :: Enumerable.t()
  def subsets([]), do: [[]]

  def subsets([x | xs]) do
    subsets = subsets(xs)

    Stream.map(subsets, fn subset -> [x | subset] end)
    |> Stream.concat(subsets)
  end
end
