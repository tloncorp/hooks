!:
|=  [=event:h =bowl:h]
^-  outcome:h
=+  ;;(emoji=cord (~(gut by config.bowl) 'emoji' ':thumbsup:'))
=+  ;;(delay=@dr (~(gut by config.bowl) 'delay' ~s30))
=-  &+[[[%allowed event] -] state.hook.bowl]
^-  (list effect:h)
?.  ?=(?(%wake %on-post) -.event)  ~
?:  ?=(%wake -.event)
  ?>  ?=(^ channel.bowl)
  =+  !<(trigger=event:h data.event)
  ?.  ?=([%on-post %add *] trigger)  ~
  =*  post  post.trigger
  =/  =c-react:c  [%add-react id.post author.post emoji]
  ~[[%channels %channel nest.u.channel.bowl %post c-react]]
?.  ?=([%on-post %add *] event)  ~
=/  id  (rsh [3 48] eny.bowl)
~[[%wait id id.hook.bowl !>(event) (add now.bowl delay)]]