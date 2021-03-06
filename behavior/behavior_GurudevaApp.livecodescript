﻿script "behavior_GurudevaApp"

global gAllQuotes,gQuoteSets, gCurrentQuoteSet, gCurrentQuote, gCurrentCategory, gCurrentQuoteID
global gQuotePickerFlag,gShowIsRunning --  gImageLoc handled in cd 2 now, gReport not used
global gCurrentAudio --jg

constant cMoveSpeed = 400 -- DTB
constant cGroupMoveDistance = 400 -- DTB

local sNextImg -- jg: filename of cached img ready to display; loaded after current img is shown
local sPlayerID -- jg: audio player ID used in playback handlers
local sPhotos -- jg: list of photos on disk, refreshed each session
local sHistoryList --jg: cr-delimited list of last 10 quotes
local sSearchResults

local sNextRandomQuote -- cached random quote for quicker retrieval

------- ###### Initialization Procedures ####---------


command initializeInterface
   set the defaultstack to "Gurudeva"
   
   -- DTB hacks
   --set the height of me to 736 -- hack to fix size issue on El Capitan
   -- End DTB hacks
   
   # make sure the UI is cleared
   # can do other things here later as needed
   
   if isMobile() then  -- jg
      if the platform = "iphone" then
         iphoneSetAudioCategory "playback" -- play when suspended or screen locked; Android doesn't need this
      end if
   else
      set the dontUseQT to true --jg: only need this once on startup
   end if
   hide group "quoteControl" of card "main-view"
   hide group "favorites-controls" of card "main-view"
   hide group "statusMessageControls" of card "main-view"
   hide btn "audioToggle" of cd "audio"
   hide grc "show controller" of cd "audio"
   hide grc "oval" of bg "topNavigation"
   if isMobile() and item 3 of the screenrect > 500 then
      set the right of bg "topNavigation" to item 1 of the working screenrect
   end if
   set the uActiveAudioSelection of cd "audio" to empty
   --  setRenderingParameters --jg: not using acceleratedRendering; issues on Android
   put 0 into gShowIsRunning # otherwise we can't roll the next set.
end initializeInterface

command getAndDistributeCategories
   try
      set the defaultstack to "Gurudeva"
      # the current model is to keep the categories as a delimited file 
      # as part of the app files: tab and pipe delimited
      
      # read the file into the all categories CustomProperty and Global
      # we parse out all the quotes into the twelve categories from the start
      # places all quotes for each category into a custom property
      # those reduces all processing time for display
      # favorites will have to be save to disk
      # this routine runs everytime the app opens
      # possibly using arrays will be more efficient, but I've never
      # found it easier than just parsing small delimited text files.
      
      # on the web server the latest quote set is here:
      # devhap/public_html/media/apps/gurudeva/gurudeva-quotes.txt
      # We are fetching it manually and placing this in the 
      
      -- jg: textDecode the data file to fix scrambled unicode characters:
      put textDecode(url ("binfile:" & DocumentsPath()& "gurudeva-quotes.txt"),"UTF8") into gAllQuotes  --jg: need binary data for decoding
      replace numtochar(13) with LF in gAllQuotes --jg: so it shows right in the VW
      --  set the uAllQuotes of me to gAllQuotes --jg: don't store; we get these from files now
      
      # Big Parser coming now... 
      
      put the uCategories of this stack into tCategories
      
      # must be tab delimited
      
      # we have to step through  all the lines of the all quotes
      # if the category is present then we pass it off to a variable
      # then load them into the custom props
      
      --  set the linedelimiter to "|"
      --  set the itemdelimiter to tab
      --  repeat for each line x in gAllQuotes --jg: takes 8 seconds on Android
      --    repeat for each item y in tCategories
      --      put "t" & y & "Set" into tAggregatedSet
      --      if (item 6 of x contains y) then put x & "|" after gQuoteSets[y]
      --    end repeat
      --  end repeat
      
      set the linedelimiter to "|"
      put "" into gQuoteSets
      repeat for each line x in gAllQuotes --jg: this is faster
         set the itemdel to tab
         put item 6 of x into tCurCats
         if the number of words in tCurCats = 0 then next repeat -- no category
         set the itemdel to comma
         repeat for each item y in tCurCats
            put x & "|" after gQuoteSets[word 1 to -1 of y]  -- strip spaces
         end repeat
      end repeat
      
      if dev() then --jg: only do this in IDE; don't need in app
         put keys(gQuoteSets) into tCategories
         set the linedelimiter to cr
         repeat for each line y in tCategories
            put y & " quotes: " & the number of lines of gQuoteSets[y] & cr after tCountCheck
         end repeat
         put tCountCheck into url ("file:"& documentsPath() & "quote-spread-stats.txt")
      end if
   catch n
      put n
   end try
   
end getAndDistributeCategories


########### Main View  Commands and Functions ##########
# driving the primary app function: 
# show photos and show quotes.

on cacheNextImg -- jg; puts a filename into script local variable sNextImg
   --### moved filename calculation out of getNextGurudevaPhoto handler so we can cache imgs
   --### ahead of time. If we decide not to use pre-caching this handler will still work,
   --### just delete the last line.
   
   --  put the imageCacheLimit into tLimit
   --  set the imageCacheLimit to 0 -- flush cache
   --  set the imageCacheLimit to tLimit -- restore original size
   put (localPath()&"img/gurudeva") into tGDPhotosFolder
   --  if the shiftkey is down and dev() then put "" into sPhotos -- dev reset
   if sPhotos = "" then --###jg: only access these once and store them for reference to save time
      set the defaultfolder to tGDPhotosFolder
      put the files into tPhotos
      filter tPhotos with "*.jpg"
      put tPhotos into sPhotos -- store in script local var
   end if
   # Random selection from Gurudeva photo set
   # no relation to category choices.
   
   put (tGDPhotosFolder &"/"& any line of sPhotos) into sNextImg -- file name
   prepare image file sNextImg -- cache it
end cacheNextImg


on getNextGurudevaPhoto pDir
   -- pDir = "left" or "right"; determines direction of vis effect
   if  (gShowIsRunning = 0) then  # we can start another one; otherwise do nothing
      
      put 1 into gShowIsRunning  # things are happening flag
      if the vis of grp "searchControls" then revealSearchControls false --jg
      
      put getNextHistoryQuote(pDir) into tNextQuote -- pull from history if available, otherwise get a random one
      set the itemDel to tab
      if (gCurrentQuote <> "") and (item 2 of tNextQuote = gCurrentQuote) then -- reached end of history list; bail out
         moveWidePhoto (the width of img "currentGDPhoto")
         put 0 into gshowisrunning
         exit getNextGurudevaPhoto
      end if
      local tNewWidth
      
      hide group "quoteControl" of card "main-view"
      hide group "favorites-controls" of card "main-view"
      set the defaultstack to "gurudeva" # in case we are calling from a substack during dev
      if the platform = "android" then --jg: visual effects with imgs are broken in android
         lock screen 
      else
         lock screen for visual effect in rect \
               (0,0,(the width of this card),(the height of this card - 46))
      end if
      
      # set up the new view now; photos, then quote
      # then reveal ... we changed all "reveal"s to scroll because "reveal" effect has lots of issues
      
      --jg: these 3 lines work with cacheNextImg to get the next img:
      if sNextImg = "" then cacheNextImg -- grab new img
      set the lockLoc of img "currentGDPhoto" to false
      set the filename of image "currentGDPhoto" of card "main-view" to sNextImg
      
      # now we have to do a lot of math magic to take any image of any size and
      # resize based on original ratio Current hard wired to iPhone 6 
      
      put the height of img "currentGDPhoto" into tOrigImgHeight
      put the width of img "currentGDPhoto" into tOrigImgWidth
      
      resizeToHeight tOrigImgHeight,tOrigImgWidth
      set the lockLoc of img "currentGDPhoto" to "true"
      set the loc of img "currentGDPhoto" to the loc of this card
      
      if the platform = "android" then -- visual effects break in android
         unlock screen 
      else -- use it on other platforms
         put "scroll" && pDir && "very fast" into tEffect
         unlock screen with visual effect tEffect
    end if
      
      cacheNextImg --jg: prepare next one
      send "getRandomQuote tNextQuote" to me in 0
   end if
end getNextGurudevaPhoto

on resizeToHeight tOrigImgHeight,tOrigImgWidth  --jg:  replaces hard-coded pixel values with variables
   put (the height of this cd)/tOrigImgHeight  into tRatio
   put (tOrigImgWidth * tRatio) into tNewWidth
   put (tOrigImgHeight * tRatio) into tNewHeight
   set the rect of img "currentGDPhoto" to 0,0,tNewWidth,tNewHeight  
end resizeToHeight

on resizeToWidth tOrigImgHeight,tOrigImgWidth --jg: used for "fit to screen" when tapped
   put the width of this cd into tW
   put tW/tOrigImgWidth into tRatio 
   put (tOrigImgWidth * tRatio) into tNewWidth
   put (tOrigImgHeight * tRatio) into tNewHeight
   set the rect of img "currentGDPhoto" to 0,0,tNewWidth,tNewHeight
end resizeToWidth

on toggleImgSize pFullSize -- if param is empty we toggle it; otherwise set it as specified;
   -- called from main img script when tapped and when main cd closes to reset
   if pFullSize = "" then -- calculate if it's already full size
      put (the height of img "currentGDPhoto" >= the height of this cd) into tFullSize
   end if
   put the formattedWidth of img "currentGDPhoto" into tFWd
   put the formattedHeight of img "currentGDPhoto" into tFHt
   if tFullSize then -- reduce to fit
      resizeToWidth tFHt,tFWd
   else -- return to full size
      resizeToHeight tFHt,tFWd
   end if
   set the loc of img "currentGDPhoto" to the loc of this cd
   set the vis of group "quoteControl" to not tFullSize
end toggleImgSize

function getNextHistoryQuote pDir -- pull a quote from the history list, store both ID and text
   --jg: pDir = "left" or "right"; left is next quote, right is previous one;
   --jg: we pull quotes from sHistoryList unless it's empty or we're
   --jg: already at the top of the list. If so, get a random one.
   set the lineDelimiter to (cr & "|")
   put lineoffset(gCurrentQuote,sHistoryList) into tLineNum
   switch pDir
      case "left" -- more recent quote, move up the list
         if gCurrentQuote is in line 1 of sHistoryList then -- no newer quotes, get a random one
            return empty
         else -- get next newer
            return line tLineNum-1 of sHistoryList
         end if
         break
      case "right" -- older quote, move down the list
         if line tLineNum + 1 of sHistoryList = "" then -- end of list
            return line tLineNum of sHistoryList  -- will send empty if list is empty --###SHOULD NOT HIDE/REPLACE
         else
            return line tLineNum + 1 of sHistoryList
         end if
         break
      default
         return empty
   end switch
end getNextHistoryQuote

Command getRandomQuote pQuote
  
   --jg: if pQuote is empty, get a random one, otherwise
   --jg: use the one passed from the history list
   if the short name of this cd <> "main-view" then exit getRandomQuote --jg
   try -- avoids error if user navigates away quickly
      --    put the rect of group "quoteControl" into tQuoteSpace --jg: moved down so we can show loading msg on launch
      --    lock screen for visual effect in rect tQuoteSpace
      --    set the blendlevel of group "quoteControl" to 0
      --    show group "quoteControl"
      
      set the linedelimiter to "|"
      set the itemdelimiter to tab
      if pQuote <> "" then -- use history quote
         put pQuote into tOneQuoteData
      else -- get random quote; save to history
         # on start up, the gCurrentCatogory will be empty
         # We need to declare the category 
         # and pass the quotes to the current working set
         # Same case if user choose "All" from categories
         
         if (gCurrentCategory is empty) OR (gCurrentCategory is "All") then 
            put "all" into gCurrentCategory
            put gAllQuotes into gCurrentQuoteSet --jg: we should remove this to save RAM; value is already in gAllQuotes
         end if
         
         if gCurrentCategory is "Favorites" then
            put url ("file:" & localPath() & "users-favorite-quotes.txt") into  gCurrentQuoteSet
         end if
         
         # Otherwise the current quote set will be set elsewhere to
         # the quotes for a specific category. see Categories card.
         if the number of words in sNextRandomQuote > 0 then -- used cached quote for speed
            put sNextRandomQuote into tOneQuoteData
         else
            put  ( line (random ( the number of lines of gCurrentQuoteSet) ) of gCurrentQuoteSet) into tOneQuoteData
         end if
         saveHistoryQuote tOneQuoteData
      end if
      # We have to think about favorites and tweets and face book 
      # So we will track the quote ID
      put item 1 of tOneQuoteData into gCurrentQuoteID
      put item 2 of tOneQuoteData  into gCurrentQuote
      
      put the rect of group "quoteControl" into tQuoteSpace
      lock screen for visual effect in rect tQuoteSpace
      set the blendlevel of group "quoteControl" to 0
      show group "quoteControl"
      #    put "â€œ" & item 2 of tOneQuoteData & "â€"  into fld "quote" -- AAG: unicode gremlins here
      put quote & item 2 of tOneQuoteData & quote  into fld "quote" 
      
      # OK, run the view: photo first, wait, then quote, then stop
      
      unlock screen with visual effect scroll down fast
      wait 1 millisecond with messages -- redraw screen
      
      if  ( (the formattedheight of fld "quote") -  (the height of fld "quote") ) > 15 then -- show "more text" indicator
         --setMoreTextIndicator "on"
         if isMobile() then -- create mobile scroller
            set the vScroll of fld "quote" to 0 -- ensures correct initial alignment
            createScroller "quote" -- replaces any existing one
         end if
      else
         --setMoreTextIndicator "off"
      end if
   catch tErr
      log tErr --jg
   end try
   cacheNextRandomQuote --jg: store the next one for quick retrieval
   put "0" into gShowIsRunning
end getRandomQuote

on cacheNextRandomQuote
   set the linedelimiter to "|"
   put any line of gCurrentQuoteSet into sNextRandomQuote
end cacheNextRandomQuote


on runQuoteSearch pString -- sent from Search button in searchControls grp
   revealSearchControls false
   hideAllSlidingGrps
   focus on nothing -- removes keyboard on mobile
   put empty into  fld "textContent" of cd "textReader"
   put empty into sSearchResults
   --  put gAllQuotes into tQuotes --jg: don't need a copy
   set the linedelimiter to "|"
   set the itemdelimiter to tab
   
   repeat for each line x in gAllQuotes  -- was: tQuotes
      --    if item 2 of x contains pString then 
      if offset(pString,item 2 of x) > 0 then --jg: marginally faster
         put x & "|" after sSearchResults
      end if
   end repeat
   loadQuoteReader "searchResults", pString
end runQuoteSearch

on loadQuoteReader pSet,pString
   put "true" into  gQuotePickerFlag
   
   put empty into  fld "textContent" of cd "textReader"
   set the icon of btn "favorites" of grp "tabNavButtons" to 1264 -- heart, the default
   switch pSet
      case "Favorites"
         put url ("file:" & documentsPath() & "users-favorite-quotes.txt") into tQuotes
         put textDecode(tQuotes,"UTF8") into tQuotes --jg: restore unicode
         set the icon of btn "favorites" of grp "tabNavButtons" to 1379 -- trash can
         --jg: see note in tabNavButtons script for why we do the following:
         set the label of btn "favorites" of grp "tabNavButtons" to "Delete Favorites" --jg: icon and label are restored on closeCard
         break
      case "searchResults"
         put sSearchResults into tQuotes
         put ("Results: " & pString) into pSet # used later for the title of the display
         # not for any processing.
         break
      case "All"
         put gAllQuotes into tQuotes
         break
         
      default # we can read all the categories if we want 
         # assumes passing a valid category name to this handler
         put  gQuoteSets[pSet] into tQuotes
         
   end switch
   
   if tQuotes <> empty then
      set the linedelimiter to "|"
      set the itemdelimiter to tab
      put the number of lines in tQuotes into tReport
      if tReport > 100 then -- and isMobile() then
         wait 1 with messages
         showMessageDisplay "Getting quotes..." -- mobileBusyIndicatorStart --jg: won't draw in LC 7.1
         wait 1 with messages
      end if
      --    filter tQuotes without empty --jg: remove blank lines
      if the short name of this cd = "textReader" then lock screen --jg: if user is on this cd, don't show redraws
      --    put (1167&tab&1168&tab&1169&tab&1170&tab&1171&tab&1172&tab&1173) into tSeparateIDs
      --    put the uHTMLQuoteTemplate of fld "textContent" of cd "textReader" into tTemplate --jg: an HTML template for merging content
      --    repeat for each line x in tQuotes
      --      add 1 to  tImgCounter
      --      put item 2 of x into tQuote
      --      put item tImgCounter of tSeparateIDs into tImgID
      --      put merge(tTemplate) after tHTML --jg: merges the template with the new variables
      --      if tImgCounter = 7 then put 0 into tImgCounter
      --    end repeat
      --    set the lineDel to cr
      --    put "<p></p>" into line -2 of tHTML --jg: trailing divider
      --    set the htmltext of fld "textContent" of cd "textReader" to tHTML --jg: now we only have a single fld access
      
      --### HTMLtext fails on mobile with limited RAM, especially on long lists. Try
      --### plain text line dividers instead of imagesources:
      
      split tQuotes by column
      put tQuotes[2] into tQuotes
      set the linedelimiter to cr
      replace cr with cr & "__________" & cr & cr in tQuotes
      put tQuotes into fld "textContent" of cd "textReader"
      set the textalign of line 1 to -1 of fld "textContent" of cd "textReader" to "center"
   else
      put "No" into tReport
   end if
   put  tReport &" - " & pSet into fld "Title" of cd "textReader"
   hideMessageDisplay -- if isMobile() then mobileBusyIndicatorStop
   if the short name of this cd = "textReader" then -- search was initiated from this card
      deleteMobileControl "textContent" -- remove any existing
      if the formattedHeight of fld "textContent" > the height of fld "textContent" then
         createScroller "textContent"
      end if
   else
      go to card "TextReader"
   end if
   enableQuoteButtons
end loadQuoteReader

command addThisQuoteToFavorites
   set the linedelimiter to "|"
   --  put line (lineoffset (gCurrentQuote, gAllQuotes) ) of gAllQuotes & "|" after \
   --        url ("file:" & documentsPath() & "users-favorite-quotes.txt")
   --  put line (lineoffset (gCurrentQuote, gAllQuotes) ) of gAllQuotes into tQuote
   put gCurrentQuoteID &tab& gCurrentQuote & LF into tQuote
   --jg: now textEncode it to preserve unicode and save as binary file.
   -- Do the reverse when retrieving the file in loadQuoteReader
   put textEncode(tQuote & "|","UTF8") after \
         url ("binfile:" & documentsPath() & "users-favorite-quotes.txt")
   showMessageDisplay "Added this quote to favorites"
   clearTabHighlights
   put "favorites-controls" into tGrp
   --  wait 1 second --jg: was "send" but that can cause errors if user leaves cd
   send "setGrpVis tGrp,empty,false" to me in 2 seconds
end addThisQuoteToFavorites

on saveHistoryQuote pQuoteData --jg: FIFO; most recent quote is on top
   -- saves entire quote data (ID, text, category)
   set the linedelimiter to "|"
   put pQuoteData & cr & "|" before sHistoryList
   delete line 11 to -1 of sHistoryList -- keep only last 10 quotes
end saveHistoryQuote


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


######### Groups, Controls and Card Display Managers ##########

on setMoreTextIndicator pOnOff
   if pOnOff = "on" then
      show grc "moreTextIndicator"
   else
      hide grc "moreTextIndicator"
   end if
end setMoreTextIndicator

on setGrpVis pGrpName,pLabel, pVis --jg: manages favorites and share groups with one handler
   -- Uses "move" which eliminates visual effect issues on Android
   -- pGrpName = short name of target grp 
   -- pLabel = message label
   -- pVis = boolean
   
   set the layerMode of grp pGrpName to "dynamic"
   if pVis then -- show it
      set the top of grp pGrpName to the height of this cd
      put pLabel into fld "app-messages" 
      set the vis of grp pGrpName to true
      put the height of grp "baseControls" + the height of grp pGrpName into tVDist
      set the blendlevel of group "quoteControl" of card "main-view" to 60
      moveGrp pGrpName, -tVDist, cMoveSpeed
      highlightSelectedTab pLabel
      set the vis of grp "statusMessageControls" to pVis --jg: do it last on show, first on hide
   else -- hide it
      set the vis of grp "statusMessageControls" to pVis
      put the height of this cd - the top of grp pGrpName into tVDist
      set the blendlevel of group "quoteControl" of card "main-view" to 0
      moveGrp pGrpName, tVDist, cMoveSpeed
      set the vis of grp pGrpName to false
      clearTabHighlights
   end if
   set the layerMode of grp pGrpName to "static"
end setGrpVis

on hideAllSlidingGrps -- jg: hide all on-screen sliding grps; no vis effects
   repeat for each item i in "shareControls,favorites-controls,statusMessageControls"
      if there is a grp i then hide grp i
   end repeat
end hideAllSlidingGrps

command showMessageDisplay pMessage
   put pMessage into fld "app-messages" of bg "statusMessageControls"
   show bg "statusMessageControls" 
end showMessageDisplay

command hideMessageDisplay
   hide bg "statusMessageControls" 
end hideMessageDisplay

on showPlayer pBool --jg: handles visibility of both mobile and desktop players
   -- if audio is playing, player is shown on audio card, hidden elsewhere;
   -- pBool = boolean
   if isMobile() then
      mobileControlSet sPlayerId, "showController",pBool
      mobileControlSet sPlayerId, "visible", pBool
   else
      set the vis of player "listenToGurudeva" of bg "soundIsPlaying" to pBool
   end if
end showPlayer


######### Web Server Communications, API Calls Etc. ##########

on fetchLatestQuotes
   # Possible we will institute some versioning later
   # off the user the option to ping the server for update on Quotes content
   # fetch new quotes, without having to do a full app update.
   # Eventually we need to think about unicode though this pipeline:
   # for now we can trigger this manually while in dev...
   put url "http://dev.himalayanacademy.com/media/apps/gurudeva/gurudeva-quotes.txt"  into gAllQuotes
   --  set the uAllQuotes of  stack "Gurudeva"  to gAllQuotes --jg: check if we really need to store these; uses RAM
   put gAllQuotes into url ("file:" & documentspath()& "gurudeva-quotes.txt")
   
end fetchLatestQuotes



########### Utilities and Helper Functions ##########

function localPath
   put specialFolderPath("Resources") into  tPath
   put "/" after tPath
   return tPath
end localPath

function documentsPath
   put specialFolderPath("Documents") into  tPath
   put "/" after tPath
   return tPath
end documentsPath

function dev -- Thanks to Jacqueline Landman Gay @ HyperActive Software for this one.
   return the environment is "development"
end dev

function isMobile -- jg, for convenience
   return the environment is "mobile"
end isMobile

function randomInRange lowerLimit,upperLimit
   return random(upperLimit - lowerLimit + 1) + lowerLimit - 1
end randomInRange

command setRenderingParameters  
   --  set the alwaysbuffer of img "currentGDPhoto" of card "main-view" to true --jg: redundant
   --  set the compositorCacheLimit of this stack to 8388608  -- jg: this is lower than the default, we need more RAM
   --  set the acceleratedRendering of this stack to true
end setRenderingParameters

function fetchAudioJson --jg: getting errors with libJSON, try JSONlib
   put url ("file:"&localPath()&"audio/audioOnBoard.json") into tJson
   put textDecode(tJson,"UTF8") into tJson
   --  put jsontoArray(tJson) into aAudio
   start using stack "JSONlib" --jg: only kept in use for this handler
   put JSON_parsed (tJson) into aAudio
   stop using stack "JSONlib"
   return aAudio
end fetchAudioJson

function pingServer
   --  return url "http://www.himalayanacademy.com/ping.txt" --jg: fails on my Mac, it is UTF8 I think
   get url "http://www.himalayanacademy.com/ping.txt"
   return textDecode(it,"UTF8") --jg: required for importing any outside text
end pingServer

on centerBgImg pImgName pHeight  --### NOT YET WORKING jg: used to resize and position imgs on cds with permanent bg imgs;
   -- needed to adapt display to different screen widths, called in preOpenCard
   --  pHeight = optional defined height; if not passed, assumes cd height
   EXIT CENTERBGIMG  --###
   put item 1 of the loc of this cd into tHPos
   put item 2 of the loc of img pImgName into tVPos
   if pHeight = "" then put the height of this cd into pHeight -- so far, only Audio cd has a defined height
   
   put the formattedheight of img pImgName into tImgHt
   put the formattedwidth of img pImgName into tImgWd
   
   put pHeight/tImgHt  into tRatio
   set the width of img pImgName to (tImgWd * tRatio)
   set the height of img pImgName to (tImgHt * tRatio)
   set the loc of img pImgName to tHPos,tVPos
   
end centerBgImg

on backKey --jg: Android-only msg; follow OS expectations
   put "main-view" into tMainCd
   if the short name of this cd <> tMainCd then
      go cd tMainCd
   else
      pass backKey -- to OS; it will quit the app
   end if
end backKey


######## Optics: Eye Candy - Graphic Effects ########

on highlightSelectedTab pButton
   clearTabHighlights
   if pButton = "delete favorites" then delete word 1 of pButton --jg: hack around "delete favorites" label
   put "166,72,20" into aTabSelected["color"]
   put "normal" into aTabSelected["blendMode"]
   put 200 into aTabSelected["opacity"]
   put "gaussian" into aTabSelected["filter"]
   put 30 into aTabSelected["size"]
   put 97 into aTabSelected["spread"]
   set the outerglow of button pButton of grp "tabNavButtons" to aTabSelected
end highlightSelectedTab

on highLightSelectedAudio pAudio
   put "242,127,1" into aTabSelected["color"]
   put "colordodge" into aTabSelected["blendMode"]
   put 165 into aTabSelected["opacity"]
   set the colorOverlay of grc pAudio to aTabSelected
   show fld "duration"
end highLightSelectedAudio

on clearAudioHighlights 
   lock screen -- jg: for speed
   repeat with x = 1 to 9
      put "audio_" & x into tButton
      set  the colorOverlay of grc tButton to empty
   end repeat
   hide fld "duration"
   unlock screen
end clearAudioHighlights

end clearAudioHighlight

on clearTabHighlights
   put "Favorites,Share,Categories,Search,Options" into tTabButtons
   lock screen -- jg: for speed
   repeat for each item x in tTabButtons
      set  the outerglow of button x of grp "tabNavButtons" to empty
   end repeat
   unlock screen
end clearTabHighlights


### Called from different card contexts:
# check preopencardhandlers of different cards

on enableQuoteButtons
   put  "Favorites,Share,Search,Categories"  into pButtons --jg: option btn always visible
   repeat for each item x in pButtons
      set the disabled of button x of grp "tabNavButtons" to false
      show btn x of grp "tabNavButtons"
      set  the colorOverlay of button x of grp "tabNavButtons" to empty
   end repeat
end enableQuoteButtons

on disableQuoteButtons pButtons
   repeat for each item x in pButtons
      set the disabled of button x of grp "tabNavButtons" to "true"
      # change of UX : we want to hide the buttons completely if 
      # they are not to be used in this context
      # this is the more standard behavior
      # even when dimmed... users try to hit on them.
      hide button x of grp "tabNavButtons"
      --      put "105,58,40" into aTabSelected["color"]
      --      put "multiply" into aTabSelected["blendMode"]
      --      put 255 into aTabSelected["opacity"]
      --      set the colorOverlay of button x to aTabSelected
   end repeat
end disableQuoteButtons

on revealSearchControls pVis --jg: combined reveal/hide handlers
   -- pVis = boolean
   
   if there is no grp "searchControls" then -- unplaced on current cd; just set vis & exit
      set the vis of bg "searchControls" to pVis
      exit revealSearchControls
   end if 
   if  pVis <> false  then -- show it
      --jg: horiz centering for mobile screens:
      set the loc of grp "searchControls" to the loc of this cd
      set the bottom of grp "searchControls" to 0
      put empty into fld "searchString" of card "Main-view"
      set the vis of group "searchControls" to true
      moveGrp "searchControls", the height of grp "searchControls", cMoveSpeed
      focus on fld "searchString" --jg: force mobile keyboard
      select after fld "searchString"
      highlightSelectedTab "search"
   else -- hide it
      focus on nothing
      moveGrp "searchControls", -(the height of grp "searchControls"), cMoveSpeed
      hide group "SearchControls"
      put empty into fld "searchString"
      clearTabHighlights
   end if  
end revealSearchControls

on moveGrp pGrpName, pDistance, pSpeed -- use move instead of visual effect to prevent Android issues
   -- movement is always vertical, so horiz is always 0
   put 0,pDistance into tPt
   move grp pGrpName relative tPt in pSpeed milliseconds
end moveGrp


command moveWidePhoto tNewWidth
   try # if user leave quickly then we have to forget this...
      if tNewWidth > the width of this cd then -- jg: was "414"
         move  img "currentGDPhoto" relative -20,0 in 30 ticks 
         move  img "currentGDPhoto" relative 20,0 in 30 ticks 
      end if
   end try  
end moveWidePhoto

on redrawBgImg -- force wide bg imgs to redraw correctly on mobile;
   -- called from most cards on preOpenCard;
   -- required because LC 7 only redraws the original width of the mobile screen
   -- leaving previous img visible around a wider screen's borders.
   if not isMobile() then exit redrawBgImg
   set the width of img 1 to (the width of img 1)+1  -- bg img is always img 1
   set the width of img 1 to (the width of img 1)-1
end redrawBgImg

-- now in behavior of shareControls group
-- on shareAudio pShareChoice --jg: added; called from Share btn on Audio card
if gCurrentAudio = "" then
   answer "Select an audio to share."
   exit shareAudio
else
   put gCurrentAudio into tFileName
end if
set the itemDel to "."
delete last item of tFileName -- file extension
switch pShareChoice
   case "email"
      put "Here is a Gurudeva audio" into tSubject
      put empty into tAddress
      put "http://www.himalayanacademy.com/view/" & tFileName into tBody
      replace space with "%20" in tBody
      put cr & cr & "__________________________________" & cr & cr & "Get the Gurudeva App:" & cr &cr & \ 
            "http://www.himalayanacademy.com/apps/gurudeva" after tBody 
      revMail tAddress,,tSubject,tBody
      break
   case "tweet"
      --      answer "Twitter option coming later from David" with "OK"
      break
   case "facebook"
      --      answer "Facebook option coming later from David" with "OK"
      break
end switch
setGrpVis "shareControls","Share",false
clearTabHighlights
end shareAudio

-- now in behavior of shareControls group
-- on shareQuote pShareChoice
if the short name of this cd = "audio" then --jg: branch for audio sharing
   shareAudio pShareChoice
   exit shareQuote
end if
switch pShareChoice
   case "email"
      
      put "Here is a Gurudeva quote" into tSubject
      put empty into tAddress
      put  quote & gCurrentQuote & quote &  cr & cr  & "-- Satguru Sivaya Subramuniyaswami"  into tBody
      put cr & cr & "__________________________________" & cr & cr & "Get the Gurudeva App:" & cr &cr & \ 
            "http://www.himalayanacademy.com/apps/gurudeva" after tBody 
      revMail tAddress,,tSubject,tBody
      break
      
   case "tweet"
      --      if len(gCurrentQuote) > 140 then
      --        --### POPULATE EDIT FLD, SHOW EDITING GRP
      --      end if
      --      answer "Twitter option coming later from David" with "OK"
      break
   case "facebook"
      --      answer "Facebook option coming later from David" with "OK"
      break
end switch
setGrpVis "shareControls","Share", false
clearTabHighlights
end shareQuote


--> DEV
-
on errorDialog pErr
   if isMobile() then
      answer pErr
   else
      pass errorDialog
   end if
end errorDialog

on log pMsg
   if dev() then
      answer pMsg with "OK" and "Cancel"
      if it = "cancel" then
         exit to top
      end if
   else
      put pMsg -- to stdout
   end if
end log

-- AAG enable or disable network tracer
if the cNetworkTracerEnabled of stack "Siva-Siva-App" is true then
   ntEnableNetworkTracer
else
   ntDisableNetworkTracer
end if
end init_AppConfiguratio


function checkQuoteFits
   if  ( (the formattedheight of fld "quote") -  (the height of fld "quote") ) < 15 then
      return "true"
   else
      return "false"
   end if
end checkQuoteFits

function checkScrollDone
   put the formattedHeight of fld "quote" into tTextHeight
   put the vScroll of fld "quote" into tVscroll
   put tTextHeight - tVscroll into tBalanceToScroll
   if tBalanceToScroll < 195 then
      return   "true"
   else
      return  "false"
   end if
end checkScrollDone



