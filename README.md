## Docs

hooks are hoon functions that modify events, cause effects, and/or build state for channels.

A hook looks like this:
```
++  hook
  $:  id=id-hook
      version=%0
      name=@t
      meta=data:m
      src=@t
      compiled=(unit vase)
      state=vase
      config=(map nest config)
  ==
```

- `id` something to uniquely identify this hook by
- `version` the version this hook was written for
- `name` something to display what this hook is called
- `meta` standard metadata, title/image/desc/cover
- `src` the source code for the hook
- `compiled` the result of trying to compile the hoon to nock
- `state` a container to collect data into
- `config` the configurations for each channel for this hook

Hooks are standalone, meaning that if you add a hook it has the potential to work across any channel. We store hooks with this structure:
```
++  hooks
  $:  hooks=(map id-hook hook)
      order=(map nest (list id-hook))
      crons=(map id-hook cron)
      waiting=(map id-wait [=origin waiting-hook])
  ==
```

- `hooks` the global repository of hooks
- `order` the order in which hooks should run for a particular channel, and which hooks should run
- `crons` scheduled hooks with their own config
- `waiting` hooks that are waiting to be called and the data they need to run

Order tells us which hooks to run and in what order. This means that hooks are meant to be a "pipeline" whereby each hook returns an event that gets passed to the next hook. Or, potentially the hook signals to "stop", more on that later.

Since hooks are functions that means they take in arguments and return a result:
```
+$  args
  $:  =event
      =bowl
  ==
+$  outcome  (each return tang)
+$  return
  $:  $:  result=event-result
          effects=(list effect)
      ==
      new-state=vase
  ==
```

### args
We pass two arguments to each hook, an `event` and a `context`. An `event` looks like this:
```
+$  event
  $%  [%on-post on-post]
      [%on-reply on-reply]
      [%cron ~]
      [%wake waiting-hook]
  ==
```

So that means we have four different kinds of events:
- `on-post` happens any time a post is interacted with or added
- `on-reply` happens any time a reply is interacted with or added
- `cron` a recurrently scheduled wakeup
- `wake` a one-off wakeup, with data. comes from a hook emitting an effect (see below)

In various places in our agent, we invoke all the hooks running for that channel passing it different events. It is up to the hook itself to no-op if it's passed an event it doesn't care about. This means that a hook could potentially respond to all events which is good in case someone wants to offer a more complete "suite" and not have to juggle multiple hooks.

Hooks are also passed a `bowl` which is "ambient" state that is involved:
```
+$  bowl
  $:  channel=(unit [=nest v-channel])
      group=(unit group-ui:g)
      channels=v-channels
      =hook
      =config
      now=time
      our=ship
      src=ship
      eny=@
  ==
```

- `channel` is the current channel this hook is running on, which includes things like posts, permissions, sort, arranged posts, etc, and it's identifier, the nest. this is null in a cron hook that has no origin.
- `group` a data structure with all of the group data associated with this channel. this is null in a cron hook that has no origin.
- `channels` all the channels we currently host (including the one above)
- `hook` this is the data representing the hook itself, mostly used to access its persisted data in `state`
- `config` the relevant config for this channel if any
- `now` the current time
- `our` the current ship this hook is running on
- `src` the ship which triggered the event
- `eny` entropy for doing things like random number generation, encryption, etc.

The `event` and `bowl` are likely everything a hook needs to run. At this time there is no way for a hook to scry out or retrieve data from the rest of the system. This may change in the future, but will be the case for now.

### return
Once the hook runs we get an `outcome` which is a wrapper around the data the hook could potentially return, telling us about the execution itself.
`+$  outcome  (each return tang)`

We do this because a hook could need to "error" out and in that case it will only return an error message and no effects/state changes/etc. However, if a hook is successful we'll get the following type:
```
+$  return
  $:  $:  result=event-result
          effects=(list effect)
      ==
      new-state=vase
  ==
```

It has three parts, starting with simplest first:

`new-state` the new persisted data for this hook which is simply placed back inside the hook itself. This means that a hook can hold things like aggregates, lists of old messages, or maybe even game state!

`result` whether to pass the event along or not, and a new potentially transformed event to be passed to any subsequent hooks
```
+$  result
  $%  [%allowed new=event]
      [%denied msg=(unit cord)]
  ==
```

If the hook returns `denied` it can optionally give a message about why. This will give us a way to return feedback to the user, but there currently is no mechanism to use this (hopefully soon).

`effects` external actions to be taken with other agents, think of this as most of the current Tlon "API"
```
+$  effect
  $%  [%channels =a-channels]
      [%groups =action:g]
      [%activity =action:a]
      [%dm =action:dm:ch]
      [%club =action:club:ch]
      [%contacts =action:co]
      [%wait waiting-hook]
  ==
```

This means that a hook can do anything that the current host has permission to do across any of these agents on the host. For example, if we wanted to automatically ban a user who includes slurs in their messages the hook would return a `%groups` action with the ban and send that to our groups agent. Assuming we're an admin or the host, the action will go through and that person will be banned.

Similarly, this could be used to make "proto-bots" where a hook parses the incoming message and then "denies" adding it, and instead sends a new message to `%channels` with the result of the parsed incoming message.

Finally the special case effect `%wait` allows a hook to be executed at a later time. It has to create an `id` associated with this particular execution so that it can be recalled later. It specifies what time it wakes up using the `fires-at` field, and it places whatever data it wants into the `data` field, likely the `event` it was passed but not necessarily.


### Looking forward
If you squint hard enough, this starts to look a lot like gall/arvo which is pretty interesting. While it's much more limited than those, you could see how we could "filter" the functionality we want from those w/o exposing the rest so that we can offer a simpler controlled execution environment.

The biggest thing hooks currently lack is a way to scry data from other agents and some way to make HTTP requests. Both of these could be pretty easily implemented using the effects + events system. However, these also begin to show the need for a "permissions" system. Especially if we allow hooks to be shared across the network. You don't want a hook to be able to scrape and exfiltrate all the data on your ship without you knowing, so we'd need some protections against that. Again this starts to look like the "userspace permissions" that gall has been needing for a long time.

Additionally, we currently don't have a way to account for loops you can create using the effects system. This could easily bring down a ship if we're not careful. We need to know if an action coming in is caused by a hook that just ran. One way around this is to maybe filter out channel actions we know would cause such a thing and instead of sending them to `%channels` to eventually cause a hook to fire, we just execute the actions directly within `%channels-server` without calling hooks. This would not prevent an action chain of a hook running on channel A sending a post to channel B which in turn runs a hook which sends a post to channel A. This would cause a loop undetected by the previous method, so some work needs to be done here.

Overall, I'm pretty confident the structure we've come up with allow us a huge degree of flexibility and power so that we can create really unique channel experiences without having to modify our backend frequently.

## Usage
We have the following API:
```
+$  id  @uv
+$  origin  $@(~ nest)
+$  config  (map @t *)
+$  action
  $%  [%add name=@t src=@t]
      [%edit =id name=(unit @t) src=(unit @t) meta=(unit data:m)]
      [%del =id]
      [%order =nest seq=(list id)]
      [%config =id =nest =config]
      [%wait =id =origin schedule=$@(@dr schedule) =config]
      [%rest =id =origin]
  ==
+$  response
  $%  [%set =id name=@t src=@t meta=data:m error=(unit tang)]
      [%gone =id]
      [%order =nest seq=(list id)]
      [%config =id =nest =config]
      [%wait =id =origin schedule=$@(@dr schedule) =config]
      [%rest =id =origin]
  ==
```
Full types here: https://github.com/tloncorp/tlon-apps/blob/029a90b9ccf075d38508ea409231df63116654e0/desk/sur/hooks.hoon

These should be poked into `%channels-server` using the mark `hook-action-0` which looks like this from the dojo:

```
:channels-server &hook-action-0 [nest action]
```

But it's better to use the provided threads so that you can get responses associated with your pokes:

```
-groups!hook-add 'name' '<src>'
-groups!hook-edit id `'name' `'<src>' `meta
-groups!hook-del id
-groups!hook-order nest [id1 id2 id3 ~]
-groups!hook-configure id nest (my ['emoji' !>(':clown_face:')] ['delay' !>(~s5)] ~)
-groups!hook-schedule id nest [%start ~s30 <some-config>]
-groups!hook-schedule id nest [%stop ~]
```

In the course of working with hooks you likely want to to test them before actually enabling them:
```
-groups!hooks-run <event> [%origin nest optional-state optional-config] <src>
-groups!hooks-run <event> [%context some-context] <src>
```

This will run your hook on it's own with the data you provide and spit out the result to the dojo. It will not have any affect on your channels/data, simply a pure function execution.

**Going one by one:**
`-groups!hook-add 'name' '<src>'` this thread creates a hook and grabs the ID generated from it's creation so you can operate on it further. `src` should be the text of a `hoon` that looks like this:
```
|=  [=event:h context:h]
^-  outcome:h
=-  &+[[[%allowed event] -] state.hook]
?.  ?=(%cron -.event)  ~
^-  (list effect:h)
=+  ;;(delay=@dr (~(gut by config) 'delay' ~s30))
=/  cutoff  (sub now delay)
?~  channel  ~
%+  murn
  (tap:on-v-posts:c (lot:on-v-posts:c posts.u.channel ~ `cutoff))
|=  [=id-post:c post=(unit v-post:c)]
^-  (unit effect:h)
?~  post  ~
`[%channels %channel nest.u.channel %post %del id-post]
```

You can see that the hook is a gate which takes an `event` and `context`. It returns an `outcome`.
This hook is meant to be run as a `cron` on a schedule to remove messages older than the `delay` in the config.

We handle config using raw nouns, which means that you need to "clam" `;;(...)` them to get the actual type you want to work with. We do that on this line:
`=+  ;;(delay=@dr (~(gut by config) 'delay' ~s30))`

So we're converting the raw noun in the config to a `@dr` and giving it the face `delay` and pinning that to the subject so we can use it further down.

This hook only returns effects which are post deletions on the channel it's running on. It allows the action to go through without modifying the event and also just returns whatever state the hook had previously, which in this case is unused.

`-groups!hook-edit id name src meta` the edit hook accepts the following arguments:
`[=id:h name=(unit @t) src=(unit @t) meta=(unit data:meta)]` The ID is the hook's ID you want to edit. All the other arguments are optional.

`-groups!hook-del id` this hook will delete the hook with associated ID

`-groups!hook-order nest [id1 id2 id3 ~]` this is how you bind a hook to a channel so that it runs. The hooks associated with a channel will run in order of this list passing the event to each subsequent hook. This list should always be the total list of hooks you want running for a particular channel. The `nest` here is the channel identifier which can be found on the web app in the URL bar when visiting said channel looks like this
`http://localhost/apps/groups/groups/~bospur-davmyl-nocsyx-lassul/better-demo/channels/chat/~bospur-davmyl-nocsyx-lassul/new-test`

The last three segments make up the `nest` `chat/~bospur-davmyl-nocsyx-lassul/new-test` and in hoon looks like `[%chat ~bospur-davmyl-nocsyx-lassul %new-test]`.

`-groups!hook-configure id nest (my ['emoji' !>(':clown_face:')] ['delay' !>(~s5)] ~)` id and nest are the same as the previous threads. The last argument is a `config` which is of type `(map @t *)` meaning you can put any noun you want inside. These are used to control variables within hooks so that they can be more general. In this example:

```
(my ['emoji' !>(':clown_face:')] ['delay' !>(~s5)] ~)
```

we're setting the value for two pieces of config, one the emoji to react with and the next is a time to wait before reacting. when we're in the hook we access config like this:

```
|=  [=event:h =context:h]
^-  outcome:h
=+  ;;(emoji=cord (~(gut by config.context) 'emoji' ':thumbsup:'))
=+  ;;(delay=@dr (~(gut by config.context) 'delay' ~s30))
::  ...
```

the `gut by` here lets us pull out the value with a default (in case this config gets cleared somehow), and then we clam the value returned using `;;` this lets us cast the raw noun to a type. finally we pin the clammed nouns to the subject so we can use them.

```
-groups!hook-schedule id nest [%start ~s30 <some-config>]
-groups!hook-schedule id nest [%start [~2000.1.1 ~s30] <some-config>]
-groups!hook-schedule id nest [%stop ~]
```
These threads use id and nest similar to the above. The final argument is whether you want to start or stop the scheduled hook, and if starting what period of time to be repeated and any config you may want to use. Additionally you can also pass a specific start time and the hook will fire at that time and then every period after that.

```
-groups!hooks-run <event> [%origin nest optional-state optional-config] <src>
-groups!hooks-run <event> [%context some-context] <src>
```
The final threads provided are so that you can test compiling and running your hook without actually affecting a channel. You first pass an event which looks like:
```
::
::  $event: the data associated with the trigger of a hook
::
::    $on-post: a post was added, edited, deleted, or reacted to
::    $on-reply: a reply was added, edited, deleted, or reacted to
::    $cron: a scheduled wake-up
::    $wake: a delayed invocation of the hook called with metadata about
::           when it fired, its id, and the event it should run with
::
+$  event
  $%  [%on-post on-post]
      [%on-reply on-reply]
      [%cron ~]
      [%wake waiting-hook]
  ==
::
::  $on-post: a hook event that fires when posts are interacted with
+$  on-post
  $%  [%add post=v-post]
      [%edit original=v-post =essay]
      [%del original=v-post]
      [%react post=v-post =ship react=(unit react)]
  ==
::
::  $on-reply: a hook event that fires when replies are interacted with
+$  on-reply
  $%  [%add parent=v-post reply=v-reply]
      [%edit parent=v-post original=v-reply =memo]
      [%del parent=v-post original=v-reply]
      [%react parent=v-post reply=v-reply =ship react=(unit react)]
  ==
::
```

the `v-post`, `v-reply`, `essay`, `memo` and `react` types can be found here: https://github.com/tloncorp/tlon-apps/blob/48549cd3e38395bb89dee1a0ed6d313e0c4079bc/desk/sur/channels.hoon

next you pass either an `%origin` or `%context`, if passing `%origin`, you need to give an `origin` which looks like `$@(~ nest)` and optionally you can give a vase for state and a config. these last two are unitized so you'll have to pass them like:

```
[%origin origin `!>(<some state>) `(my ['some-config' ~s30] ~)]
```

this will use the `origin` you give to generate a `context` using data from the agent, which is passed to the hook as an argument. alternatively you can pass a full `context` if you need to control the exactly what data is in the `context`. you can do so like:

```
[%context context]
```

Finally, you pass the source code of the hook as a hoon `cord` or `@t`. The easiest way to do so is to start a multi-line cord in the dojo with `'''` then paste your source code, hit enter and then put another `'''` . this will combine your source code into a single line cord that you can pass to the thread.