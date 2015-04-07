
# Rift
### Healing the rift between Elixir and Thrift.

Thrift's erlang implementation isn't very pleasant to use in Elixir. It prefers records to structs, littering your code with tuples. It swalllows enumerations you've defined, banishing them to the realm of wind and ghosts. It requires that you write a bunch of boilerplate handler code, and client code that's not very Elixir-y. Rift fixes this.

Rift Provides three modules, `Rift.Struct`, `Rift.Client`, and `Rift.Server` which will help you manage this impedence mismatch.


## Elixir-style structs with `Rift.Struct`

`Rift.Struct` provides functionality for converting Thrift types into Elixir structs.

You tell `Rift.Struct` about your Erlang Thrift modules and which structs you would like to import. It then looks at the thrift files, parses their metadata and builds Elixir structs for you. It also creates `to_elixir` and `to_erlang` functions that will handle converting Erlang records into Elixir structs and vice versa.

Assuming you have a Thrift module called `pinterest_types` in your `src` directory:

```elixir
  defmodule Structs do
    use Rift.Struct, pinterest_types: [:User, :Pin, :Board]
  end
```

Then you can do the following:

```elixir
user = Structs.User.new(firstName: "Stinky", lastName: "Stinkman")
user_tuple = Structs.to_erlang(user)
> {:User, "Stinky", "Stinkman"}

Structs.to_elixir(user_tuple)
> %Structs.User{firstName: "Stinky", lastName: "Stinkman"}

```

...but you'll rarely use the Struct module directly. Instead, you'll use the `Rift.Client` or `Rift.Server` modules.


## Generating Servers with `Rift.Server`

`Rift.Server` assumes you have a module that has a bunch of handler functions in it. When a thrift RPC is called, your parameters will be converted into Elixir structs and then passed in to one of your handler functions. Let's assume you have the following thrift defined:

```thrift
enum UserState {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: string username,
  2: string firstName,
  3: string lastName;
  4: UserState state;
}

service PinterestRegister {
  User register(1: string firstName, 2: string lastName);
  bool isRegistered(1: User user);
  UserState getState(1: string username);
  void setState(1: User user, 2: UserState state);
}
```

You can set it up like this:


```elixir
defmodule Server do
    use Rift.Server, service: :pinterest_thrift,
    structs: Data,
    functions: [register: &ThriftHandlers.register/3,
                isRegistered: &ThriftHandlers.is_registered/1,
                getState: &ThriftHandlers.get_state/1,
                setState: &ThriftHandlers.set_state/2
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
	  :active -> 1
	  :inactive -> 2
	  :banned -> 3
	end
  
    enumerize_struct User, state: UserState
    enumerize_function setUserState(_, UserState)
    enumerize_function getState(_), returns: UserState
end

defmodule ThriftHandlers do
  
  def register(username, first_name, last_name) do
     # registration logic. Return a new user
     Data.User.new(username: username, firstName: "Stinky", lastName: "Stinkman")
  end

  def is_registered(user=%Data.User{}) do
     true
  end

  def get_state(username) do
     user = Models.User.fetch(username)
     Data.UserState.new(user: user, state: :active)
  end
  
  def set_state(user=%Data.User{}, state=%Data.UserState{}) do
	  ...
  end

end
```

The server is doing a bunch of work for you. It's investigating your thrift files and figuring out which structs need to be imported by looking at the parameters, exceptions and return values. It then makes a module that imports your structs (`Data` in this case) and builds code for the thrift server that takes an incoming thrift request, converts its parameters into Elixir representations and then calls your handler. Notice how the handlers in ThriftHandlers take structs as arguments and return structs. That's what Rift gets you.

These handler functions also process the values your code returns and hands them back to thrift.

The above example also shows how to handle Thrift enums.  Due to the way thrift enums are handled by the erlang generator, there's no way for Rift to convert them into a friendly structure for you, so they need to be defined and pointed out to Rift. 

The server is configured in the server block. The first element of the tuple is the module of the server you wish to instantiate. The second element is a Keyword list of configuration options for the server. You cannot set the :name, :handler or :service params. The name and handler are set to the current module. The service is given as the thrift_module option.


## Generating a client with `Rift.Client`

Generating a client is similarly simple. `Rift.Client` just asks that you point it at the erlang module that was generated by thrift, tell it what the client's configuration is and tell it what functions you'd like to import. When that's done, it examines the thrift module, figures out what types you need, creates structs for them and generates helper functions for calling your thrift RPC calls.

Assuming the same configuration above, the following block will generate a client:

```elixir
     defmodule RegisterClient do
       use Rift.Client, 
         structs: Models,
         client_opts: [host: "localhost", port: 1234, framed: true],
         service: :pinterest_thrift, 
         import [:register, :isRegistered, :getState]
     end
```
     
You start the client by calling start_link: 

```elixir     
     RegisterClient.start_link 
```
     
You can then issue calls against the client:
    
```elixir    
     user = RegisterClient.register("Stinky", "Stinkman")
     > %Models.User{firstName: "Stinky", lastName: "Stinkman")
     is_registered = RegisterClient.isRegistered(user)
     > true
```
     
Clients support the same callbacks and enumeration transformations that the server suports, and they're configured identically.


## Handling Thrift Enumerations

Unfortunately, enumeration support in Erlang thrift code is lossy and because of this Rift can't tell where the enumerations you worked so tirelessly to define appear in the generated code. Because of this, you have to re-define them and tell Rift where they are; otherwise, all you'll see are integers. 

To do this, Rift supports a syntax to re-define enumerations, and this syntax is available when you use `Rift.Server` and `Rift.Client`.

The following examples assume these RPC calls and enumeration:

```thrift    
    enum DayOfTheWeek {
    	SUNDAY,
    	MONDAY,
    	TUESDAY,
    	WEDNESDAY,
    	THURSDAY,
    	FRIDAY
    }

    void setCreatedDay(1: User user, 2: DayOfTheWeek day)
    DayOfTheWeek getCreatedDay(1: User user);
```

First off, you'll need to re-define your enumeration. To do that, use the defenum macro inside of your `Rift.Server` or `Rift.Client` module:

```elixir
		defenum DayOfTheWeek do
		   :sunday -> 1
		   :monday -> 2
		   :tuesday -> 3
		   :wednesday -> 4
		   :thursday -> 5
		   :friday -> 6
		   :saturday -> 7
	  	end
```

##### Converting enumerations in structs
Now you'll need to tell Rift where this enum appears in your other data structures. To do that, use the enumerize_struct macro:

     enumerize_struct User, sign_up_day: DayOfTheWeek, last_login_day: DayOfTheWeek
     
Now all Users will have their sign_up_day and last_login_day fields automatically converted to enumerations.
     
##### Converting enumerations in functions

If the enumeration is the argument or return value of a RPC call, you'll need to identify it there too. Use the `enumerize_function` macro:

    enumerize_function setCreatedDay(_, DayOfTheWeek)
    enumerize_function getCreatedDay(_) returns: DayOfTheWeek

The `enumerize_function` macro allows you to mark function arguments and return values with the enumeration you would like to use. Unconverted arguments are signaled by using the `_` character. In the example above, setCreatedDay's second argument will be converted to a DayOfTheWeek enumeration and its first argument will be left alone.

Similarly, the function `getCreatedDay` will have its argument left alone and its return value converted into a DayOfTheWeek enumeration
   
##### Using enumerations in code
Enumerations are maps whose modules support converting between the map and integer representation. This shows how to convert integers to enumerations and vice-versa

```elixir
    x = DayOfWeek.monday
    > %DayOfWeek{ordinal: :monday, value: 2}
    x.value
    > 1
    x = DayOfWeek.value(4)
    > %DayOfWeek{ordinal: :thursday, value: 4}
    x.ordinal
    > :thursday
```

Since they're just maps, enumerations can be pattern matched against.

```elixir
    def handle_user(user=%User{sign_up_day: DayOfTheWeek.monday}) do
      # code for users that signed up on monday
    end
    
    def handle_user(user=%User{})
      # code for everyone else
    end
```