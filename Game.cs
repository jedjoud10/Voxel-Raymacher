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
using ImGuiNET;
using System.Runtime.InteropServices.Marshalling;

namespace Test123Bruh {
    internal class Game : GameWindow {
        int fbo;
        int screenTexture;
        int scaleDownFactor = 1;
        Compute compute = null;
        ImGuiController controller = null;
        Voxel voxel = null;
        Movement movement = null;
        Skybox skybox = null;

        int maxLevelIter = Voxel.levels-1;
        int maxIter = 128;
        int maxReflections = 1;
        float reflectionRoughness = 0.02f;
        int debugView = 0;
        bool useSubVoxels = false;
        bool useMipchainCacheOpt = false;
        bool usePropagatedBoundsOpt = false;
        ulong frameCount = 0;
        Vector3 lightDirection = new Vector3(1f, 1f, 1f);
        float[] frameGraphData = new float[512];
        
        private static void OnDebugMessage(
            DebugSource source,     // Source of the debugging message.
            DebugType type,         // Type of the debugging message.
            int id,                 // ID associated with the message.
            DebugSeverity severity, // Severity of the message.
            int length,             // Length of the string in pMessage.
            IntPtr pMessage,        // Pointer to message string.
            IntPtr pUserParam)      // The pointer you gave to OpenGL, explained later.
        {
            string message = Marshal.PtrToStringAnsi(pMessage, length);
            Console.WriteLine("[{0} source={1} type={2} id={3}] {4}", severity, source, type, id, message);
            if (type == DebugType.DebugTypeError) {
                throw new Exception(message);
            }
        }

        public Game(GameWindowSettings gameWindowSettings, NativeWindowSettings nativeWindowSettings) : base(gameWindowSettings, nativeWindowSettings) {
        }

        protected override void OnLoad() {
            base.OnLoad();
            CursorState = CursorState.Grabbed;

            GL.DebugMessageCallback(OnDebugMessage, 0);
            GL.Enable(EnableCap.DebugOutput);
            GL.Enable(EnableCap.TextureCubeMapSeamless);
            GL.Enable(EnableCap.DebugOutputSynchronous);

            screenTexture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, screenTexture);
            GL.TextureStorage2D(screenTexture, 1, SizedInternalFormat.Rgba8, ClientSize.X, ClientSize.Y);

            fbo = GL.GenFramebuffer();
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, fbo);
            GL.NamedFramebufferTexture(fbo, FramebufferAttachment.ColorAttachment0, screenTexture, 0);

            compute = new Compute("Basic.glsl");
            voxel = new Voxel();
            controller = new ImGuiController(ClientSize.X, ClientSize.Y);
            movement = new Movement();
            skybox = new Skybox();
        }

        protected override void OnFramebufferResize(FramebufferResizeEventArgs e) {
            base.OnFramebufferResize(e);

            GL.DeleteTexture(screenTexture);

            screenTexture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, screenTexture);
            GL.TextureStorage2D(screenTexture, 1, SizedInternalFormat.Rgba8, e.Width, e.Height);
            GL.NamedFramebufferTexture(fbo, FramebufferAttachment.ColorAttachment0, screenTexture, 0);
            GL.Viewport(0, 0, e.Width, e.Height);
            controller.WindowResized(e.Width, e.Height);
        }

        protected override void OnTextInput(TextInputEventArgs e) {
            base.OnTextInput(e);
            controller.PressChar((char)e.Unicode);
        }

        protected override void OnMouseWheel(MouseWheelEventArgs e) {
            base.OnMouseWheel(e);
            controller.MouseScroll(e.Offset);
        }

        // Capture a screenshot and save to a folder next to the executable
        private void Screenshot() {
            string execPath = System.Reflection.Assembly.GetEntryAssembly().Location;
            execPath = Path.GetDirectoryName(execPath);
            string dirPath = Path.Combine(execPath, "Screenshots");
            var time = DateTime.Now.ToString("yyyy-MM-dd-HH-mm-ss") + ".jpg";
            Directory.CreateDirectory(dirPath);
            string ssPath = Path.Combine(dirPath, time);

            GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);

            var bitmap = new System.Drawing.Bitmap(ClientSize.X, ClientSize.Y);
            var data = bitmap.LockBits(new System.Drawing.Rectangle(0, 0, ClientSize.X, ClientSize.Y), ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            GL.ReadPixels(0, 0, ClientSize.X, ClientSize.Y, PixelFormat.Bgra, PixelType.UnsignedByte, data.Scan0);
            bitmap.UnlockBits(data);
            bitmap.RotateFlip(System.Drawing.RotateFlipType.RotateNoneFlipY);
            File.Create(ssPath).Dispose();
            bitmap.Save(ssPath, ImageFormat.Jpeg);
        }

        // Render ImGui Stuff!!!
        private void ImGuiDebug(float delta) {
            bool t = true;
            ImGui.Begin("Voxel Raymarcher Test Window!", ref t, ImGuiWindowFlags.MenuBar);
            ImGui.Text("Frame timings: " + delta + ", FPS: " + (1.0 / delta));
            ImGui.Text("F5: Toggle Fullscreen");
            ImGui.Text("F4: Toggle Normal/Grabbed Mouse");
            ImGui.Text("F3: Take screenshot and save it as Jpeg");
            ImGui.ListBox("Debug View Type", ref debugView, new string[] {
                "Non-Debug", "Map intersection normal", "Total iterations",
                "Max mip level fetched", "Total bit fetches", "Total reflections", "Normals", "Global Position", "Local Position", "Sub-voxel Local Position" }, 10);
            ImGui.SliderInt("Max Iters", ref maxIter, 0, 512);
            ImGui.PlotLines("Time Graph", ref frameGraphData[0], 512);
            ImGui.SliderInt("Starting Mip-chain Depth", ref maxLevelIter, 0, Voxel.levels - 1);
            ImGui.SliderInt("Max Ray Reflections", ref maxReflections, 0, 10);
            ImGui.SliderFloat("Reflection Roughness", ref reflectionRoughness, 0.0f, 0.4f);
            ImGui.ListBox("Resolution Scale-down Factor", ref scaleDownFactor, new string[] {
                "1x (Native)", "2x", "4x",
                "8x" }, 4);
            ImGui.Checkbox("Use Sub-Voxels (bitmask)?", ref useSubVoxels);
            ImGui.Checkbox("Use Mip-chain Ray Cache Octree Optimization?", ref useMipchainCacheOpt);
            ImGui.Checkbox("Use Propagated AABB Bounds Optimization?", ref usePropagatedBoundsOpt);
            ImGui.Text("Map Size: " + Voxel.size);
            ImGui.Text("Map Max Levels: " + Voxel.levels);
            ImGui.Text("Map Memory Usage: " + (voxel.memoryUsage/(1024*1024)) + "mb");

            System.Numerics.Vector3 v = new System.Numerics.Vector3(lightDirection.X, lightDirection.Y, lightDirection.Z);
            ImGui.SliderFloat3("Sun direction", ref v, -1f, 1f);
            lightDirection.X = v.X;
            lightDirection.Y = v.Y;
            lightDirection.Z = v.Z;
            ImGui.End();            

            //ImGui.DockSpaceOverViewport();
            //ImGui.ShowDemoWindow();
        }

        protected override void OnRenderFrame(FrameEventArgs args) {
            base.OnRenderFrame(args);
            frameCount += 1;
            float delta = (float)args.Time;
            frameGraphData[frameCount % 512] = delta;

            controller.Update(this, delta);
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);
            GL.ClearColor(new Color4(0, 32, 48, 255));
            GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit | ClearBufferMask.StencilBufferBit);

            // Player movement and matrices
            if (CursorState == CursorState.Grabbed) {
                movement.Move(MouseState, KeyboardState, delta);
            }
            movement.UpdateMatrices((float)ClientSize.Y / (float)ClientSize.X);
            
            // Fullscreen toggle 
            if (KeyboardState.IsKeyPressed(Keys.F5)) {
                WindowState = 3 - WindowState;
            }
            
            // Cursor toggle
            if (KeyboardState.IsKeyPressed(Keys.F4)) {
                CursorState = 2 - CursorState;
            }

            // Bind compute shader and execute it
            GL.UseProgram(compute.program);
            int scaleDown = 1 << scaleDownFactor;
            GL.BindImageTexture(0, screenTexture, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rgba8);
            GL.ProgramUniform2(compute.program, 1, ClientSize.ToVector2() / scaleDown);
            GL.ProgramUniformMatrix4(compute.program, 2, false, ref movement.viewMatrix);
            GL.ProgramUniformMatrix4(compute.program, 3, false, ref movement.projMatrix);
            GL.ProgramUniform3(compute.program, 4, movement.position);
            GL.ProgramUniform1(compute.program, 5, maxLevelIter);
            GL.ProgramUniform1(compute.program, 6, maxIter);
            GL.ProgramUniform1(compute.program, 7, Voxel.size);
            GL.ProgramUniform1(compute.program, 8, debugView);
            GL.ProgramUniform1(compute.program, 9, maxReflections);
            GL.ProgramUniform1(compute.program, 10, useSubVoxels ? 1 : 0);
            GL.ProgramUniform1(compute.program, 11, reflectionRoughness);
            GL.ProgramUniform3(compute.program, 12, lightDirection.Normalized());
            GL.ProgramUniform1(compute.program, 13, useMipchainCacheOpt ? 1 : 0);
            GL.ProgramUniform1(compute.program, 14, usePropagatedBoundsOpt ? 1 : 0);
            voxel.Bind(1);

            GL.BindTextureUnit(2, skybox.texture);
            int x = (int)MathF.Ceiling((float)(ClientSize.X / scaleDown) / 32.0f);
            int y = (int)MathF.Ceiling((float)(ClientSize.Y / scaleDown) / 32.0f);
            GL.DispatchCompute(x, y, 1);
            GL.BlitNamedFramebuffer(fbo, 0, 0, 0, ClientSize.X / scaleDown, ClientSize.Y / scaleDown, 0, 0, ClientSize.X, ClientSize.Y, ClearBufferMask.ColorBufferBit, BlitFramebufferFilter.Nearest);

            ImGuiDebug(delta);
            controller.Render();

            // Screenshotting
            if (KeyboardState.IsKeyPressed(Keys.F3)) {
                Screenshot();
            }

            ImGuiController.CheckGLError("End of frame");
            SwapBuffers();
        }
    }
}
