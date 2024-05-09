using OpenTK.Windowing.Desktop;
using OpenTK.Windowing.Common;

namespace Test123Bruh {
    internal class Program {
        static void Main(string[] args) {
            var windowSettings = new GameWindowSettings();
            var nativeWindowSettings = new NativeWindowSettings() {
                ClientSize = (800, 600),
                WindowState = WindowState.Normal,
                Flags = ContextFlags.ForwardCompatible
            };
            

            using (Game game = new Game(windowSettings, nativeWindowSettings)) {
                game.Run();
            }
        }
    }
}
