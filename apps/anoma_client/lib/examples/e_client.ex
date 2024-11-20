defmodule Anoma.Client.Examples.EClient do
  @moduledoc """
  I contain functions to test the public interface of the client.

  I start a new client and if necessary a node, and then connect to that node.

  I test the public GRPC interface of the client to ensure it works as expected.
  """
  use TypedStruct

  alias __MODULE__
  alias Anoma.Client
  alias Anoma.Node.Examples.ENode
  alias Anoma.Protobuf.Indexer.Nullifiers
  alias Anoma.Protobuf.Indexer.UnrevealedCommits
  alias Anoma.Protobuf.Indexer.UnspentResources
  alias Anoma.Protobuf.Intent
  alias Anoma.Protobuf.IntentPool.AddIntent
  alias Anoma.Protobuf.IntentPool.ListIntents
  alias Anoma.Protobuf.Intents
  alias Anoma.Protobuf.Input
  alias Anoma.Protobuf.Prove

  import ExUnit.Assertions

  ############################################################
  #                    Context                               #
  ############################################################

  typedstruct do
    @typedoc """
    I am the state of a TCP listener.

    My fields contain information to listen for TCP connection with a remote node.

    ### Fields
    - `:channel`    - The channel for making grpc requests.
    - `:supervisor` - the pid of the supervision tree.
    - `:node`       - The node to which the client is connected.
    - `:client`     - The client that is connected to the node.
    - `:channel`    - The channel for making grpc requests.
    """
    field(:supervisor, pid())
    field(:node, ENode.t())
    field(:client, Client.t())
    field(:channel, any())
  end

  typedstruct module: EConnection do
    @typedoc """
    I am an example GRPC stub connection to a client.
    I represent an outside client (e.g., a typescript application).

    ### Fields
    - `:channel`    - The channel for making grpc requests.
    """
    field(:channel, any())
  end

  ############################################################
  #                    Helpers                               #
  ############################################################

  @doc """
  I create a new node in the system, and ensure that that is the only node that is running
  by killing all other nodes.
  """
  @spec create_single_example_node() :: ENode.t()
  def create_single_example_node() do
    ENode.kill_all_nodes()
    ENode.start_node(grpc_port: 0)
  end

  @doc """
  I kill the existing client.
  """
  @spec kill_existing_client() :: :ok
  def kill_existing_client() do
    Client.ConnectionSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} -> Supervisor.stop(pid) end)
  end

  @doc """
  I create an instance of the client and connect it to the given node.

  If there is already a client started, I kill it and start a new one.
  """
  @spec create_example_client(ENode.t() | nil) :: EClient.t()
  def create_example_client(enode \\ create_single_example_node()) do
    kill_existing_client()

    {:ok, client} = Client.connect("localhost", enode.grpc_port, 0)

    %EClient{supervisor: nil, client: client, node: enode}
  end

  @doc """
  I create an example stub to a given clients GRPC endpoint.
  """
  @spec create_example_connection() :: EConnection.t()
  def create_example_connection(eclient \\ create_example_client()) do
    case GRPC.Stub.connect("localhost:#{eclient.client.grpc_port}") do
      {:ok, channel} ->
        %EConnection{channel: channel}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  I create the setup necessary to run each example below without arguments.
  """
  @spec setup() :: EConnection.t()
  def setup() do
    create_example_connection()
  end

  ############################################################
  #                    Examples                              #
  ############################################################

  @doc """
  I list the intents over grpc on the client.
  """
  @spec list_intents(EConnection.t()) :: EConnection.t()
  def list_intents(conn \\ setup()) do
    request = %ListIntents.Request{}
    {:ok, _reply} = Intents.Stub.list_intents(conn.channel, request)
    conn
  end

  @doc """
  I add an intent to the client.
  """
  @spec add_intent(EConnection.t()) :: EConnection.t()
  def add_intent(conn \\ setup()) do
    request = %AddIntent.Request{intent: %Intent{value: 1}}

    {:ok, _reply} = Intents.Stub.add_intent(conn.channel, request)

    # fetch the intents to ensure it was added
    request = %ListIntents.Request{}

    {:ok, reply} = Intents.Stub.list_intents(conn.channel, request)

    assert reply.intents == ["1"]

    conn
  end

  @doc """
  I list all nullifiers.
  """
  @spec list_nullifiers(EConnection.t()) :: EConnection.t()
  def list_nullifiers(conn \\ setup()) do
    request = %Nullifiers.Request{}
    {:ok, _reply} = Intents.Stub.list_nullifiers(conn.channel, request)

    conn
  end

  @doc """
  I list all unrevealed commits.
  """
  @spec list_unrevealed_commits(EConnection.t()) :: EConnection.t()
  def list_unrevealed_commits(conn \\ setup()) do
    request = %UnrevealedCommits.Request{}

    {:ok, _reply} =
      Intents.Stub.list_unrevealed_commits(conn.channel, request)

    conn
  end

  @doc """
  I list all unspent resources.
  """
  @spec list_unspent_resources(EConnection.t()) :: EConnection.t()
  def list_unspent_resources(conn \\ setup()) do
    request = %UnspentResources.Request{}

    {:ok, _reply} =
      Intents.Stub.list_unspent_resources(conn.channel, request)

    conn
  end

  @doc """
  I run a plaintext nock program using the client.
  """
  @spec prove_something_text(EConnection.t()) :: Prove.Response.t()
  def prove_something_text(conn \\ setup()) do
    program = text_program_example()
    input = text_input("1")

    request = %Prove.Request{
      program: {:text_program, program},
      public_inputs: [input]
    }

    {:ok, result} = Intents.Stub.prove(conn.channel, request)

    assert {:ok, <<123>>} == Noun.Jam.cue(elem(result.result, 1))

    result
  end

  @doc """
  I run a jammed nock program using the client.
  """
  @spec prove_something_jammed(EConnection.t()) :: Prove.Response.t()
  def prove_something_jammed(conn \\ setup()) do
    program = Noun.Jam.jam([[1 | 123], 0 | 0])
    input = jammed_input(Noun.Jam.jam(1))

    request = %Prove.Request{
      program: {:jammed_program, program},
      public_inputs: [input]
    }

    {:ok, result} = Intents.Stub.prove(conn.channel, request)

    assert {:ok, <<123>>} == Noun.Jam.cue(elem(result.result, 1))

    result
  end

  @doc """
  I run a Juvix program that squares its inputs.
  """
  @spec run_juvix_factorial(EConnection.t()) :: Prove.Response.t()
  def run_juvix_factorial(conn \\ setup()) do
    # assume the program and inputs are jammed
    program = jammed_program_juvix_squared()
    input = jammed_input(Noun.Jam.jam(3))

    request = %Prove.Request{
      program: {:jammed_program, program},
      public_inputs: [input]
    }

    {:ok, result} = Intents.Stub.prove(conn.channel, request)

    assert {:ok, <<9>>} == Noun.Jam.cue(elem(result.result, 1))

    result
  end

  ############################################################
  #                           Helpers                        #
  ############################################################

  @spec jammed_program_juvix_squared() :: binary()
  def jammed_program_juvix_squared() do
    :code.priv_dir(:anoma_client)
    |> Path.join("test_juvix/Squared.nockma")
    |> File.read!()
  end

  @spec noun_program_juvix_squared() :: Noun.t()
  def noun_program_juvix_squared() do
    jammed_program_juvix_squared()
    |> Noun.Jam.cue()
    |> elem(1)
  end

  @spec text_program_example() :: binary()
  def text_program_example() do
    "[[1 123] 0 0]"
  end

  @spec jammed_program_example() :: binary()
  def jammed_program_example() do
    noun_program_example()
    |> Noun.Jam.jam()
  end

  @spec noun_program_example() :: Noun.t()
  def noun_program_example() do
    text_program_example()
    |> Noun.Format.parse_always()
  end

  @spec text_program_minisquare() :: binary()
  def text_program_minisquare() do
    "[[1 123] 0 0]"
  end

  @spec jammed_program_minisquare() :: binary()
  def jammed_program_minisquare() do
    noun_program_minisquare()
    |> Noun.Jam.jam()
  end

  @spec noun_program_minisquare() :: Noun.t()
  def noun_program_minisquare() do
    text_program_minisquare()
    |> Noun.Format.parse_always()
  end

  @spec jammed_input(any()) :: Input.t()
  def jammed_input(value \\ <<>>) do
    %Input{input: {:jammed, value}}
  end

  @spec text_input(any()) :: Input.t()
  def text_input(value \\ "") do
    %Input{input: {:text, value}}
  end
end
