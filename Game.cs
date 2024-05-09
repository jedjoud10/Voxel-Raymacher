using OpenTK.Graphics.OpenGL4;
using OpenTK.Windowing.Common;
using OpenTK.Windowing.Desktop;
using OpenTK.Mathematics;
using System.Runtime.InteropServices;
using OpenTK.Windowing.GraphicsLibraryFramework;
using System.Runtime.Serialization;
using System.Drawing.Imaging;
using System.IO;
using PixelFormat = OpenTK.Graphics.OpenGL4.PixelFormat;

namespace Test123Bruh {
    internal class Game : GameWindow {
        int fbo;
        int screenTexture;
        Compute compute;
        Quaternion rotation;
        Vector3 position = new Vector3(0.0f, 2.0f, 0.0f);
        Matrix4 projMatrix;
        Matrix4 viewMatrix;
        Vector2 mousePosTest;
        int selector;
        bool toggle;
        int scaleDown = 4;
        Voxel voxel = null;
        double last;

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
            voxel = new Voxel();
            


            base.OnLoad();
        }

        protected override void OnFramebufferResize(FramebufferResizeEventArgs e) {
            base.OnFramebufferResize(e);

            GL.DeleteTexture(screenTexture);

            screenTexture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, screenTexture);
            GL.TextureStorage2D(screenTexture, 1, SizedInternalFormat.Rgba8, e.Width, e.Height);
            GL.NamedFramebufferTexture(fbo, FramebufferAttachment.ColorAttachment0, screenTexture, 0);
        }

        protected override void OnUpdateFrame(FrameEventArgs args) {
            base.OnUpdateFrame(args);

            // Clear background (will get overwritten anyways)
            GL.ClearColor(Color4.Black);
            GL.Clear(ClearBufferMask.ColorBufferBit);

            // Update rotation
            CursorState = CursorState.Grabbed;
            mousePosTest += MouseState.Delta * 0.0006f;
            rotation = Quaternion.FromAxisAngle(Vector3.UnitY, -mousePosTest.X) * Quaternion.FromAxisAngle(Vector3.UnitX, -mousePosTest.Y);
            //rotation = Quaternion.FromEulerAngles(-mousePosTest.Y, -mousePosTest.X, 0.0f);

            Vector3 forward = Vector3.Transform(-Vector3.UnitZ, rotation);
            Vector3 up = Vector3.Transform(Vector3.UnitY, rotation);
            Vector3 side = Vector3.Transform(Vector3.UnitX, rotation);

            // Update position and rotation
            float speed = 30f;
            float delta = (float)(args.Time - last);
            if (KeyboardState.IsKeyDown(Keys.W)) {
                position += forward * speed * delta;
            } else if (KeyboardState.IsKeyDown(Keys.S)) {
                position += -forward * speed * delta;
            }
            
            if (KeyboardState.IsKeyDown(Keys.A)) {
                position += -side * speed * delta;
            } else if (KeyboardState.IsKeyDown(Keys.D)) {
                position += side * speed * delta;
            }

            // Fullscreen toggle
            if (KeyboardState.IsKeyPressed(Keys.F5)) {
                toggle = !toggle;
                WindowState = toggle ? WindowState.Fullscreen : WindowState.Normal;
            }

            // Debugger
            if (KeyboardState.IsKeyPressed(Keys.F4)) {
                selector += 1;
                selector = selector % 7;
            }

            // Create a rotation and position matrix based on current rotation and position
            viewMatrix = Matrix4.CreateFromQuaternion(rotation);
            projMatrix = Matrix4.CreatePerspectiveFieldOfView(MathHelper.DegreesToRadians(70.0f), (float)ClientSize.Y / (float)ClientSize.X, 0.1f, 1000.0f); 

            // Bind compute shader and execute it
            GL.UseProgram(compute.program);
            GL.ProgramUniform2(compute.program, 1, ClientSize.ToVector2() / scaleDown);
            GL.ProgramUniformMatrix4(compute.program, 2, false, ref viewMatrix);
            GL.ProgramUniformMatrix4(compute.program, 3, false, ref projMatrix);
            GL.ProgramUniform3(compute.program, 4, position);
            GL.ProgramUniform1(compute.program, 5, selector);
            GL.ActiveTexture(TextureUnit.Texture0);
            GL.BindImageTexture(0, screenTexture, 0, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.Rgba8);
            voxel.Bind(compute.program);
            int x = (int)MathF.Ceiling((float)(ClientSize.X / scaleDown) / 32.0f);
            int y = (int)MathF.Ceiling((float)(ClientSize.Y / scaleDown) / 32.0f);
            GL.DispatchCompute(x, y, 1);

            // Copy texture back to main FBO
            GL.BlitNamedFramebuffer(fbo, 0, 0, 0, ClientSize.X / scaleDown, ClientSize.Y / scaleDown, 0, 0, ClientSize.X, ClientSize.Y, ClearBufferMask.ColorBufferBit, BlitFramebufferFilter.Nearest);
            
            // Screenshotting
            if (KeyboardState.IsKeyPressed(Keys.F3)) {
                string execPath = System.Reflection.Assembly.GetEntryAssembly().Location;
                execPath = Path.GetDirectoryName(execPath);
                string dirPath = Path.Combine(execPath, "Screenshots");
                var time = DateTime.Now.ToString("yyyy-MM-dd-HH-mm-ss") + ".jpg";
                Directory.CreateDirectory(dirPath);
                string ssPath = Path.Combine(dirPath, time);

                GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);

                var bitmap = new System.Drawing.Bitmap(ClientSize.X, ClientSize.Y);
                var data = bitmap.LockBits(new System.Drawing.Rectangle(0, 0, ClientSize.X, ClientSize.Y), ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                GL.ReadPixels(0, 0, ClientSize.X, ClientSize.Y, PixelFormat.Rgba, PixelType.UnsignedByte, data.Scan0);
                bitmap.UnlockBits(data);
                bitmap.RotateFlip(System.Drawing.RotateFlipType.RotateNoneFlipY);
                File.Create(ssPath).Dispose();
                bitmap.Save(ssPath, ImageFormat.Jpeg);
            }

            SwapBuffers();
        }
    }
}
