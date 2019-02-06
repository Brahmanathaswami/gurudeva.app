script "lib_MobileControls"

######### Mobile Controls ############

command CreateScroller pName -- scrolling fields
  if not isMobile() then exit CreateScroller
  deleteMobileControl pName -- delete any existing
  put (the rect of control pName) into tRect
  mobileControlCreate "scroller", pName
  mobileControlSet pName, "rect", tRect
  put  ("0,0," & (the formattedwidth of control pName) & "," & the formattedheight of control pName) into tRect
  mobileControlSet pName, "contentRect" , tRect
  mobileControlSet pName, "hScroll" , 0
  mobileControlSet pName, "vScroll" , 0
  mobileControlSet pName, "hIndicator" , false
  if pName = "quote" then
     mobileControlSet pName, "vIndicator", true
  end if
  mobileControlSet pName, "visible",  true
end CreateScroller

on scrollerDidScroll hScrolled, vScrolled
  put mobileControlTarget() into tControlID
  set the vscroll of control tControlID to vscrolled
  pass scrollerDidScroll
end scrollerDidScroll

on deleteMobileControl pName -- jg: deletes an existing mobile control
  -- native controls should be deleted if possible when no longer needed, as
  -- they are overlaid on the stack and will float over all cards
  if not isMobile() then exit deleteMobileControl -- do nothing on desktop
  repeat while pName is among the lines of mobileControls()
    mobileControlDelete pName
  end repeat
end deleteMobileControl

on createMobileAudioPlayer pURL
  if sPlayerID is in mobileControls() then mobileControlDelete sPlayerID -- init
  mobileControlCreate "player"
  put the result into sPlayerId
  -- adjust location for mobile:
  put the rect of player "listenToGurudeva" into tRect
  put (the bottom of img 1) - 10 into item 4 of tRect
  put item 4 of tRect -  50 into item 2 of tRect
  mobileControlSet sPlayerId, "rect", tRect
  mobileControlSet sPlayerId, "showController", true 
  mobileControlSet sPlayerId, "filename", pURL 
  mobileControlSet sPlayerId, "visible", true 
  if pURL begins with "http" then
    mobileBusyIndicatorStart "square", "Loading audio..." -- add loading indicator until duration is available
  end if
  if mobileIdleTimerLocked() is false then mobileLockIdleTimer --jg: disallow screen lock
end createMobileAudioPlayer 

on playerPropertyAvailable theProperty -- msg sent when enough has content is loaded
  if theProperty is "duration" then
    mobileBusyIndicatorStop -- Remove the "Loading..." indicator and start playing
    if the platform = "android" then
      show grc "Show Controller" of cd "audio"
    end if
    mobileControlDo sPlayerId, "play"
  end if
end playerPropertyAvailable

on setMobileAudioPlayer pState --jg: control the state of the mobile player
  -- pState = "pause", "play", or "stop"
  mobileControlDo sPlayerId, pState
  if pState = "stop" then
    mobileBusyIndicatorStop -- in case it's still showing
    mobileControlSet sPlayerId, "visible", false
    mobileControlDelete sPlayerId
    if mobileIdleTimerLocked() is true then mobileUnlockIdleTimer
    hide grc "Show Controller" of cd "audio"
  end if
end setMobileAudioPlayer

on playerFinished -- sent on mobile when audio is done; reset icon
  if there is a grp "soundIsPlaying" then hide grp "soundIsPlaying"
  hide grc "Show Controller" of cd "audio"
  if mobileIdleTimerLocked() is true then mobileUnlockIdleTimer
end playerFinished

on playStopped -- sent on desktop when audio is done
  if there is a grp "soundIsPlaying" then hide grp "soundIsPlaying"
end playStopped
