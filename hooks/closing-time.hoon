|=  [=event:h =bowl:h]
^-  outcome:h
|^
=*  hook  hook.bowl
:: Define our default configuration values
=+  ;;(open-time=@dr (~(gut by config.bowl) 'open-time' ~h11))
=+  ;;(close-time=@dr (~(gut by config.bowl) 'close-time' ~h11.m30))
=+  ;;(open-msg=cord (~(gut by config.bowl) 'open-msg' 'The channel is now open.'))
=+  ;;(close-msg=cord (~(gut by config.bowl) 'close-msg' 'The channel is now closed.'))
=+  !<(channels-open=(map nest:c ?) state.hook)
:: Only respond to cron events
?.  ?=(%cron -.event)  &+[[[%allowed event] ~] state.hook]
:: If there's no channel, we can't do anything
?~  channel.bowl  &+[[[%allowed event] ~] state.hook]
=*  nest  nest.u.channel.bowl
:: Extract the current channel state from our hook state
=/  channel-open=?  (~(gut by channels-open) nest |)
:: Convert current time to hours within the day (0-23.xx)
=/  current-hour=@dr  (mod now.bowl ~d1)
:: Calculate whether the channel should be open based on time
=/  should-be-open=?
  ?:  (gth open-time close-time)
    :: Crossing midnight case (e.g., open 22:00, close 06:00)
    |((gte current-hour open-time) (lth current-hour close-time))
  :: Normal case (e.g., open 09:00, close 17:00)
  &((gte current-hour open-time) (lth current-hour close-time))
:: Generate effects based on state changes
=/  effects=(list effect:h)
  ?:  =(should-be-open channel-open)
    :: No change needed
    ~
  ?:  should-be-open
    :: Channel is opening
    :~  [%channels %channel nest %post %add (create-essay open-msg)]
        [%channels %channel nest %del-writers (sy %admin ~)]
    ==
  :: Channel is closing
  :~  [%channels %channel nest %post %add (create-essay close-msg)]
      [%channels %channel nest %add-writers (sy %admin ~)]
  ==
:: Return the new state and effects
&+[[[%allowed event] effects] !>((~(put by channels-open) nest should-be-open))]
::  Helper gate to create an essay from a message
++  create-essay
  |=  msg=cord
  ^-  essay:c
  :*  :+  ~[[%inline ~[msg]]]
        our.bowl  :: Use our ship as author
        now.bowl
      [%chat ~]
  ==
--