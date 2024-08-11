using OpenTK.Windowing.Desktop;
using OpenTK.Windowing.Common;

namespace Test123Bruh {
    internal class Program {
        static void Main(string[] args) {
            var windowSettings = new GameWindowSettings() {
                UpdateFrequency = 60,
            };
            var nativeWindowSettings = new NativeWindowSettings() {
                ClientSize = (800, 600),
                WindowState = WindowState.Normal,
                APIVersion = new Version(4, 6),
                Flags = ContextFlags.Debug | ContextFlags.ForwardCompatible,
                //Vsync = VSyncMode.On,
            };

            using (Game game = new Game(windowSettings, nativeWindowSettings)) {
                game.Run();
            }

            //Console.WriteLine(Class1.CalculateDensityAndSonicSpeed(100, 0));
        }
    }
}
