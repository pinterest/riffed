=======
Rift
=======

Healing the rift between Elixir and Thrift.

Thrift's erlang implementation is very erlangy, preferring records to maps. As a result, it can be confusing and difficult to use in Elixir. Rift fixes this.

Rift Provides two modules, `Rift.Struct` and `Rift.Server` which will help you manage this impedence mismatch.


#### Rift.Struct

You tell `Rift.Struct` about your Erlang Thrift modules and which structs you would like to import. It then looks at the thrift files, parses their metadata and builds Elixir structs for you. It also creates `to_elixir` and `to_thrift` functions that will handle converting Erlang records into Elixir structs and vice versa. 

Assuming you have a Thrift module called `pinterest_types` in your `src` directory:

```elixir
  defmodule Structs do
    use Rift.Struct, pinterest_types: [:User, :Pin, :Board]
  end
```

Then you can do the following: 

```
user = Structs.User.new(firstName: "Stinky", lastName: "Stinkman")
user_tuple = Structs.to_erlang(user)
> {:User, "Stinky", "Stinkman"}

Structs.to_elixir(user_tuple)
> %Structs.User{firstName: "Stinky", lastName: "Stinkman"}

```

#### Generating Servers with `Rift.Server`

`Rift.Server` assumes you have a module that has a bunch of handler functions in them. When a thrift RPC is called, your parameters will be converted into Elixir structs and then passed in to one of your handler functions. Let's assume you have the following thrift defined:

```thrift
struct User {
  1: string firstName,
  2: string lastName;
}

service PinterestRegister {
  User register(1: string firstName, 2: string lastName);
  bool isRegistered(1: User user)
}
```

You can set it up like this:


```elixir
defmodule Server do
    use Rift.Server, thrift_module: :pinterest_thrift,
    struct_module: Data,
    functions: [register: &ThriftHandlers.register/2,
                isRegistered: &ThriftHandlers.is_registered/1
    ],

    server: {:thrift_socket_server,
             port: 2112,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }
  end

defmodule ThriftHandlers do
  def register(first_name, last_name) do
     # registration logic. Return a new user
     Data.User.new(firstName: "Stinky", lastName: "Stinkman")
  end
  
  def is_registered(user=%Data.User{}) do
     true
  end
end
```
The server is doing a bunch of work for you. It's investigating your thrift files and figuring out which structs need to be imported by looking at the parameters, exceptions and return values. It then makes a module that imports your structs (`Data` in this case) and builds code for the thrift server that takes an incoming thrift request, converts its parameters into Elixir representations and then calls your handler. 

These handler functions also process the values your code returns and hands them back to thrift. 
