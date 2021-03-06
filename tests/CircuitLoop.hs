
import Control.Monad
import Control.Monad.Trans
import Control.Arrow

import Simulation.Aivika.Trans
import Simulation.Aivika.IO

specs = Specs 0 10 1 RungeKutta4 SimpleGenerator

model :: Simulation IO ()
model =
  do let swap (x, y) = (y, x)

         k :: Circuit IO a a
         k = loop (arr swap)
         -- k = loop (arr id)

         m :: (Num a, Show a) => Circuit IO a a
         m = arrCircuit $ \a -> traceEvent (show a) (return $ 1 + a)

     runEventInStartTime $
       iterateCircuitInIntegTimes_ (k >>> m) 0

     runEventInStopTime $
       return ()

main = runSimulation model specs
