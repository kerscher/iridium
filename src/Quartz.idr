module Main

import Effect.State
import IR
import IR.Event
import IR.Workspace
import IR.Layout

%flag C "-framework Cocoa"
%include C "cbits/quartz.h"
%link C "src/quartz.o"
%include C "cbits/ir.h"
%link C "src/ir.o"

%default total

%assert_total
putErrLn : String -> IO ()
putErrLn s = fwrite stderr (s ++ "\n")

quartzInit : IO Bool
quartzInit = map (/= 0) (mkForeign (FFun "quartzInit" [] FInt))

quartzSpacesCount : IO Int
quartzSpacesCount = mkForeign (FFun "quartzSpacesCount" [] FInt)

QuartzWindow : Type
QuartzWindow = Int

QuartzState : Type
QuartzState = IRState QuartzWindow Int

instance Handler (IREffect QuartzWindow) IO where
  handle () GetEvent k = do
    p <- mkForeign (FFun "quartzEvent" [] FPtr)
    e <- eventFromPtr p
    k e ()
  handle () (HandleEvent (KeyEvent key)) k = do
    k () ()
  handle () (HandleEvent RefreshEvent) k = do
    k () ()
  handle () (HandleEvent IgnoredEvent) k = do
    k () ()
  handle () (TileWindow wid r) k = do
    mkForeign (FFun "quartzWindowSetRect" [FInt, FFloat, FFloat, FFloat, FFloat] FUnit) wid (rectX r) (rectY r) (rectW r) (rectH r)
    k () ()
  handle () GetWindows k = do
    p <- mkForeign (FFun "quartzWindows" [] FPtr)
    l <- mkForeign (FFun "quartzWindowsLength" [FPtr] FInt) p
    wids <- traverse (\a => mkForeign (FFun "quartzWindowId" [FPtr, FInt] FInt) p a) [0..l-1]
    mkForeign (FFun "quartzWindowsFree" [FPtr] FUnit) p
    k wids ()
  handle () GetFrames k = do
    p <- mkForeign (FFun "quartzMainFrame" [] FPtr)
    x <- mkForeign (FFun "irFrameX" [FPtr] FFloat) p
    y <- mkForeign (FFun "irFrameY" [FPtr] FFloat) p
    w <- mkForeign (FFun "irFrameW" [FPtr] FFloat) p
    h <- mkForeign (FFun "irFrameH" [FPtr] FFloat) p
    mkForeign (FFun "irFrameFree" [FPtr] FUnit) p
    k (0 ** [MkRectangle x y w h]) ()

instance Default QuartzState where
  default = MkIRState (MkStackSet (MkScreen (MkWorkspace Nothing) 0 (MkRectangle 0 0 0 0)) [] [])

initialColumns : Rectangle -> Workspace QuartzWindow -> { [IR QuartzWindow] } Eff IO ()
initialColumns frame (MkWorkspace Nothing) = return ()
initialColumns frame (MkWorkspace (Just stack)) = f (toList (columnLayout frame stack))
  where f ((w, r) :: xs) = do
          tileWindow w r
          f xs
        f [] = return ()

initialQuartzState : { [IR QuartzWindow, STATE QuartzState] } Eff IO ()
initialQuartzState = do
  (_ ** frame :: _) <- getFrames
  wids <- getWindows
  let workspace : Workspace QuartzWindow = foldr manage (MkWorkspace Nothing) wids
  put (MkIRState (MkStackSet (MkScreen workspace 0 frame) [] []))
  initialColumns frame workspace

partial
main : IO ()
main = do
  putStrLn "iridium started"
  a <- quartzInit
  if not a
  then do
    putErrLn "iridium doesn't have Accessibility permission."
    putErrLn "You can enable this under Privacy in Security & Privacy in System Preferences."
  else run $ do
    initialQuartzState
    runIR
