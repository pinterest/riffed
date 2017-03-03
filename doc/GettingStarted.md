# Getting Started

This guide will bring you step-by-step through building your first Riffed server and client. The service will allow for registering, fetching, and banning users. An example of the completed tutorial can be found in `examples/tutorial/`.

We'll assume you already have a Mix project to work with called `riffed_tutorial`. Feel free to go create one if you don't, using `mix new riffed_tutorial --sup`. Then add Riffed as a dependency:

```elixir
def deps do
  [{:riffed, github: "pinterest/riffed"}]
end
```

## 1. Defining thrift structs

The first step is to create the thrift specifications for the service. This means defining structs, and the methods that the service supports. But first, you have to tell your Mix project to include the thrift compiler, and also tell it where your thrift files live. Somewhere in your project definition in `mix.exs`, add the following (as appropriate):

```elixir
def project do
  [
    ...
    compilers: [:thrift | Mix.compilers],
    thrift_files: Mix.Utils.extract_files(["thrift"], [:thrift]),
    ...
  ]
end
```

This tells Riffed to look for `.thrift` files in the `thrift/` folder in your project. So go ahead and create a file `thrift/tutorial.thrift` with the following:

```thrift
enum UserState {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: i64 id;
  2: string username,
  3: UserState state = UserState.ACTIVE;
}

service Tutorial {
  i64 registerUser(1: string username);
  User getUser(1: i64 userId);
  UserState getState(1: i64 userId);
  void setState(1: i64 userId, 2: UserState state);
}
```

## 2. Building the Server

Now go ahead and create the file `lib/riffed_tutorial/server.ex`. We'll start with the contents of the file:

```elixir
defmodule RiffedTutorial.Server do
  use Riffed.Server,
  service: :tutorial_thrift,
  structs: RiffedTutorial.Models,
  functions: [registerUser: &RiffedTutorial.Handler.register_user/1,
              getUser: &RiffedTutorial.Handler.get_user/1,
              getState: &RiffedTutorial.Handler.get_state/1,
              setState: &RiffedTutorial.Handler.set_state/2
  ],
  server: {:thrift_socket_server,
           port: 2112,
           framed: true,
           max: 10_000,
           socket_opts: [
             recv_timeout: 3000,
             keepalive: true]
          }

  defenum UserState do
    :active -> 0
    :inactive -> 1
    :banned -> 2
  end

  enumerize_struct User, state: UserState
  enumerize_function setUserState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
```

Now let's stop and look at each of the keywords passed to `use Riffed.Server` to understand what's happening.

Keyword | Explanation
------- | -----------
`:service` | This tells Riffed which `.thrift` file to look at to find the service definition for this service. Notice this matches with the name of the service inside the thrift file, with an `_thrift` appended to the end.
`:structs` | This tells Riffed how to namespace the structs defined by our service. In this case, this results in the creation of the struct `%RiffedTutorial.Models.User{}`.
`:functions` | This is a keyword list that maps the thrift service method name to a method that handles it. In this case, we have yet to define the module `RiffedTutorial.Handler`, however we will shortly.
`:server` | This tells Riffed which type of thrift server to use. For details on the different types, as well as all the additional parameters you can give here, you will need to consult the [Erlang Thrift Implementation](https://github.com/apache/thrift/tree/master/lib/erl).

Next, we see a `defenum` block. Elixir does not support any form of enumeration, and so this invokes some macros built into Riffed for defining enums. Always ensure the ordering here matches with the ordering in your `.thrift` file. Well, actually the ordering is not important, but rather the values you assign are.

Lastly, there are two more macros `enumerize_struct` and `enumerize_function` which you use to tell Riffed how your enum is used. Any fields, parameters, or return values must be enumerized so Riffed will know how to convert between their base values and the enumerized values.

## 3. Building the Handler

Now that the server is configured, the method calls need to be handled. This step is where you come in; you must build the actual methods that do the server logic. In this example, we'll implement a simple ETS (Erlang Term Storage) for a user database, though typically you would add logic for connecting to your own database. In case you are unfamiliar with ETS, it "allows us to store any Erlang/Elixir term in an in-memory table" (taken from the [Elixir documentation](http://elixir-lang.org/getting-started/mix-otp/ets.html)).

Create a file `lib/riffed_tutorial/handler.ex` with the following contents:

```elixir
defmodule RiffedTutorial.Handler do
  use GenServer
  alias RiffedTutorial.Models

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge(opts, name: __MODULE__))
  end

  def init(:ok) do
    db = :ets.new(:users, [:public, :named_table, read_concurrency: true])
    {:ok, db}
  end

  def register_user(username) do
    id = :ets.info(:users, :size)
    new_user = Models.User.new(id: id, username: username)
    :ets.insert_new(:users, {id, new_user})
    id
  end

  def get_user(user_id) do
    case :ets.lookup(:users, user_id) do
      [{^user_id, user}] -> user
      [] -> :error
    end
  end

  def get_state(user_id) do
    user = get_user(user_id)
    user.state
  end

  def set_state(user_id, state) do
    user = get_user(user_id)
    new_user = %{user | state: state}
    :ets.insert(:users, {user_id, new_user})
    :ok
  end
end
```

During initialization, we created a new ETS table called `:users`. When registering a new user, we simply create a user ID by using the current size of the table. `get_state` and `set_state` should be straight-forward.

Notice the use of `Models.User.new` inside `register_user`. When creating instances of the auto-generated thrift models, it's important to use this method to ensure your struct will play nicely with thrift.

## 4. Building the Client

The next step is to build a client to connect to our server. The client will be part of the same project, and in fact running on the same host, but for example purposes this is fine. Create the file `lib/riffed_tutorial/client.ex` with the following contents:

```elixir
defmodule RiffedTutorial.Client do
  use Riffed.Client,
  auto_import_structs: false,
  structs: RiffedTutorial.Models,
  client_opts: [
    host: "localhost",
    port: 2112,
    retries: 3,
    framed: true
  ],
  service: :tutorial_thrift,
  import: [:registerUser,
           :getUser,
           :getState,
           :setState]

  enumerize_function setState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
```

It's important to notice that we have used `auto_import_structs: false`, since otherwise the client will try to redefine `RiffedTutorial.Models`. The server and client are using the same models, and so you only want them to be defined once.

### Optional Step

If you really want, you can set `auto_import_structs: false` on both the client and server modules, and define a new file containing the models directly in `lib/riffed_tutorial/models.ex`:

```elixir
defmodule RiffedTutorial.Models do
  use Riffed.Struct, tutorial_types: [:User]

  defenum UserState do
    :active -> 0
    :inactive -> 1
    :banned -> 2
  end

  enumerize_struct User, state: UserState
end
```

If you do this, you can remove the `defenum` and `enumerize_struct` parts of the server definition as well. Be sure to leave in the `enumerize_function` calls.

## 5. Setting up the Supervision Tree

The final step is to go into `lib/riffed_tutorial.ex` and add your server, client, and handler as children to be supervised:

```elixir
children = [
  worker(RiffedTutorial.Server, []),
  worker(RiffedTutorial.Client, []),
  worker(RiffedTutorial.Handler, [])
]
```

## 6. Testing

That's it! Now let's test it out! Starting the application with `iex -S mix`, here is a sample run:

```elixir
iex> RiffedTutorial.Client.registerUser("tupac")
0 # This is the newly created user id

iex> RiffedTutorial.Client.getState(0)
%RiffedTutorial.Models.UserState{ordinal: :active, value: 0}
# This is how enums get displayed in the shell

iex> RiffedTutorial.Client.setState(0, RiffedTutorial.Models.UserState.banned)
:ok

iex> RiffedTutorial.Client.getUser(0)
%RiffedTutorial.Models.User{id: 0,
 state: %RiffedTutorial.Models.UserState{ordinal: :banned, value: 2},
 username: "tupac"}
```

Now that you've completed this Getting Started tutorial, feel free to explore the other documentation, and play around with creating your own Riffed servers and clients. Happy hacking!
