using OpenTK.Graphics.OpenGL4;
using OpenTK.Windowing.Common;
using OpenTK.Windowing.Desktop;
using OpenTK.Mathematics;
using OpenTK.Compute.OpenCL;
using System.Drawing;
using System.Runtime.InteropServices;

namespace Test123Bruh {
    internal class Game : GameWindow {
        int fbo;
        int screenTexture;
        Compute compute;


        private static void OnDebugMessage(
            DebugSource source,     // Source of the debugging message.
            DebugType type,         // Type of the debugging message.
            int id,                 // ID associated with the message.
            DebugSeverity severity, // Severity of the message.
            int length,             // Length of the string in pMessage.
            IntPtr pMessage,        // Pointer to message string.
            IntPtr pUserParam)      // The pointer you gave to OpenGL, explained later.
        {
            // In order to access the string pointed to by pMessage, you can use Marshal
            // class to copy its contents to a C# string without unsafe code. You can
            // also use the new function Marshal.PtrToStringUTF8 since .NET Core 1.1.
            string message = Marshal.PtrToStringAnsi(pMessage, length);

            // The rest of the function is up to you to implement, however a debug output
            // is always useful.
            Console.WriteLine("[{0} source={1} type={2} id={3}] {4}", severity, source, type, id, message);

            // Potentially, you may want to throw from the function for certain severity
            // messages.
            if (type == DebugType.DebugTypeError) {
                throw new Exception(message);
            }
        }

        public Game(GameWindowSettings gameWindowSettings, NativeWindowSettings nativeWindowSettings) : base(gameWindowSettings, nativeWindowSettings) {
        }

        protected override void OnLoad() {
            GL.DebugMessageCallback(OnDebugMessage, 0);
            GL.Enable(EnableCap.DebugOutput);
            GL.Enable(EnableCap.DebugOutputSynchronous);

            screenTexture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, screenTexture);
            GL.TextureStorage2D(screenTexture, 1, SizedInternalFormat.Rgba8, ClientSize.X, ClientSize.Y);
            
            fbo = GL.GenFramebuffer();
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, fbo);
            GL.NamedFramebufferTexture(fbo, FramebufferAttachment.ColorAttachment0, screenTexture, 0);


            compute = new Compute("Basic.glsl");
            base.OnLoad();
        }

        protected override void OnUpdateFrame(FrameEventArgs args) {
            base.OnUpdateFrame(args);


            // Clear background (will get overwritten anyways)
            GL.ClearColor(Color4.Black);
            GL.Clear(ClearBufferMask.ColorBufferBit);

            // Bind compute shader and execute it
            GL.UseProgram(compute.program);
            GL.BindImageTexture(0, screenTexture, 0, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.Rgba8);
            GL.DispatchCompute(ClientSize.X, ClientSize.Y, 1);

            // Copy texture back to main FBO
            //GL.BindFramebuffer(FramebufferTarget.DrawFramebuffer, 0);
            GL.BlitNamedFramebuffer(fbo, 0, 0, 0, ClientSize.X, ClientSize.Y, 0, 0, ClientSize.X, ClientSize.Y, ClearBufferMask.ColorBufferBit, BlitFramebufferFilter.Nearest);


            SwapBuffers();
        }
    }
}
