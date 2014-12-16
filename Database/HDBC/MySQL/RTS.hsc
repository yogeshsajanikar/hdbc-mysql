{-# LANGUAGE EmptyDataDecls, ForeignFunctionInterface #-}

module Database.HDBC.MySQL.RTS (withRTSSignalsBlocked) where

import Control.Concurrent (runInBoundThread)
#ifndef _WIN32
import Control.Exception (finally)
import Foreign.C.Types (CInt(..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.Storable (Storable(..))
#endif

#include <signal.h>

-- | Execute an 'IO' action with signals used by GHC's runtime signals
-- blocked.  The @mysqlclient@ C library does not correctly restart
-- system calls if they are interrupted by signals, so many MySQL API
-- calls can unexpectedly fail when called from a Haskell application.
-- This is most likely to occur if you are linking against GHC's
-- threaded runtime (using the @-threaded@ option).
--
-- This function blocks @SIGALRM@ and @SIGVTALRM@, runs your action,
-- then unblocks those signals.  If you have a series of HDBC calls
-- that may block for a period of time, it may be wise to wrap them in
-- this action.  Blocking and unblocking signals is cheap, but not
-- free.
--
-- Here is an example of an exception that could be avoided by
-- temporarily blocking GHC's runtime signals:
--
-- >  SqlError {
-- >    seState = "", 
-- >    seNativeError = 2003, 
-- >    seErrorMsg = "Can't connect to MySQL server on 'localhost' (4)"
-- >  }
withRTSSignalsBlocked :: IO a -> IO a
#ifndef _WIN32
withRTSSignalsBlocked act = runInBoundThread . alloca $ \set -> do
  sigemptyset set
  sigaddset set (#const SIGALRM)
  sigaddset set (#const SIGVTALRM)
  pthread_sigmask (#const SIG_BLOCK) set nullPtr
  act `finally` pthread_sigmask (#const SIG_UNBLOCK) set nullPtr
#else
withRTSSignalsBlocked act = runInBoundThread act
#endif

#ifndef _WIN32
data SigSet

instance Storable SigSet where
    sizeOf    _ = #{size sigset_t}
    alignment _ = alignment (undefined :: Ptr CInt)

foreign import ccall unsafe "signal.h sigaddset" sigaddset
    :: Ptr SigSet -> CInt -> IO ()

foreign import ccall unsafe "signal.h sigemptyset" sigemptyset
    :: Ptr SigSet -> IO ()

foreign import ccall unsafe "signal.h pthread_sigmask" pthread_sigmask
    :: CInt -> Ptr SigSet -> Ptr SigSet -> IO ()
#endif

