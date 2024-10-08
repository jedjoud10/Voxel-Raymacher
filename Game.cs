﻿using OpenTK.Graphics.OpenGL4;
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
        Compute depthStuff = null;
        ImGuiController controller = null;
        Voxel voxel = null;
        Movement movement = null;
        Skybox skybox = null;
        int depthTex0;
        int depthTex1;
        int depthTex2;

        int maxLevelIter = 0;
        int maxIter = 64;
        int maxShadowIter = 0;
        int maxReflections = 3;
        int maxSubVoxelIter = 6;
        int maxReproIter = 32;
        float reflectionRoughness = 0.02f;
        int debugView = 0;
        bool useSubVoxels = false;
        bool useMipchainCacheOpt = false;
        bool useAABBOpt = true;
        bool useTemporalReproOpt = false;
        bool usePositionalTemporalReproOpt = false;
        ulong frameCount = 0;
        Vector3 lightDirection = new Vector3(1f, 1f, 1f);
        float[] frameGraphData = new float[512];
        Matrix4 lastFrameViewMatrix = Matrix4.Identity;
        Vector3 lastPosition = Vector3.Zero;
        bool holdTemporalValues = false;

        float ambientStrength = 0.035f;
        float normalMapStrength = 0.2f;
        float roughnessStrength = 0.5f;
        float metallicStrength = 0.5f;
        Vector3 topColor = new Vector3(44, 87, 54) / 255.0f;
        Vector3 sideColor = new Vector3(100, 84, 67) / 255.0f;
        float timeElapsed = 0.0f;
        
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

        private int CreateScreenTex(SizedInternalFormat format, int downscale = 1) {
            int tex = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, tex);
            GL.TextureStorage2D(tex, 1, format, ClientSize.X / downscale, ClientSize.Y / downscale);
            return tex;
        }

        protected override void OnLoad() {
            base.OnLoad();
            CursorState = CursorState.Grabbed;

            //GL.DebugMessageCallback(OnDebugMessage, 0);
            //GL.Enable(EnableCap.DebugOutput);
            GL.Enable(EnableCap.TextureCubeMapSeamless);
            GL.Enable(EnableCap.DebugOutputSynchronous);

            screenTexture = CreateScreenTex(SizedInternalFormat.Rgba8);
            depthTex0 = CreateScreenTex(SizedInternalFormat.R32f);
            depthTex1 = CreateScreenTex(SizedInternalFormat.R32f);
            depthTex2 = CreateScreenTex(SizedInternalFormat.R32f, 2);

            GL.Enable(EnableCap.FramebufferSrgb);
            //GL.Enable(EnableCap.Dither);
            fbo = GL.GenFramebuffer();
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, fbo);
            GL.NamedFramebufferTexture(fbo, FramebufferAttachment.ColorAttachment0, screenTexture, 0);

            compute = new Compute("Basic.glsl");
            depthStuff = new Compute("DepthDownscaler.glsl");
            voxel = new Voxel();
            controller = new ImGuiController(ClientSize.X, ClientSize.Y);
            movement = new Movement();
            skybox = new Skybox(lightDirection);
            maxLevelIter = voxel.levels - 1;
        }

        protected override void OnFramebufferResize(FramebufferResizeEventArgs e) {
            base.OnFramebufferResize(e);

            GL.DeleteTexture(screenTexture);

            screenTexture = CreateScreenTex(SizedInternalFormat.Rgba8);
            depthTex0 = CreateScreenTex(SizedInternalFormat.R32f);
            depthTex1 = CreateScreenTex(SizedInternalFormat.R32f);
            depthTex2 = CreateScreenTex(SizedInternalFormat.R32f, 2);

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
            System.Numerics.Vector3 ToVec3(Vector3 v) {
                return new System.Numerics.Vector3(v.X, v.Y, v.Z);
            }

            void FromVec3(System.Numerics.Vector3 input, ref Vector3 output) {
                output.X = input.X;
                output.Y = input.Y;
                output.Z = input.Z;
            }


            bool t = true;
            ImGui.Begin("Voxel Raymarcher Test Window!", ref t, ImGuiWindowFlags.MenuBar);
            ImGui.Text("Frame timings: " + delta + ", FPS: " + (1.0 / delta));
            ImGui.Text("F5: Toggle Fullscreen");
            ImGui.Text("F4: Toggle Normal/Grabbed Mouse");
            ImGui.Text("F3: Take screenshot and save it as Jpeg");
            ImGui.ListBox("Debug View Type", ref debugView, new string[] {
                "Non-Debug", "Map intersection normal", "Total iterations",
                "Max mip level fetched", "Total bit fetches", "Total mip-map iterations", "Total reflections", "Normals", "Global Position",
                "Local Position", "Sub-voxel Local Position", "Scene Depth (log)", "Reprojected Scene Depth (log)", "Min Depth Taken For Repro", "Total Reprojection Steps Taken (percent)" }, 14);
            ImGui.PlotLines("Time Graph", ref frameGraphData[0], 512);

            System.Numerics.Vector3 p = ToVec3(movement.position);
            ImGui.InputFloat3("Position", ref p);
            FromVec3(p, ref movement.position);

            if (ImGui.CollapsingHeader("Parameters, Limits & Optimizations")) {
                ImGui.SliderFloat("Horizontal Fov", ref movement.hFov, 0.1f, 179f);
                ImGui.SliderInt("Max Iters", ref maxIter, 0, 512);
                ImGui.SliderInt("Max Shadow Iters", ref maxShadowIter, 0, 64);
                ImGui.SliderInt("Max Sub-Voxel Iters", ref maxSubVoxelIter, 0, 6);
                ImGui.SliderInt("Starting Mip-chain Depth", ref maxLevelIter, 0, voxel.levels - 1);
                ImGui.SliderInt("Max Ray Reflections", ref maxReflections, 0, 10);
                ImGui.SliderFloat("Reflection Roughness", ref reflectionRoughness, 0.0f, 0.4f);
                ImGui.ListBox("Resolution Scale-down Factor", ref scaleDownFactor, new string[] {
                    "1x (Native)", "2x", "4x",
                    "8x" }, 4);
                ImGui.Checkbox("Use Sub-Voxels (bitmask)?", ref useSubVoxels);


                ImGui.Checkbox("Use Propagated AABB Bounds Optimization?", ref useAABBOpt);
                ImGui.Checkbox("Use Mip-chain Ray Cache Octree Optimization?", ref useMipchainCacheOpt);

                ImGui.Checkbox("Use Temporally Reprojected Depth Optimization?", ref useTemporalReproOpt);

                if (!useTemporalReproOpt)
                    ImGui.BeginDisabled();
                ImGui.Checkbox("Use Positional Reprojection ?", ref usePositionalTemporalReproOpt);
                ImGui.SliderInt("Max Positional Repro Iters", ref maxReproIter, 16, 128);
                if (!useTemporalReproOpt)
                    ImGui.EndDisabled();
                ImGui.Checkbox("Hold Temporal Values?", ref holdTemporalValues);
            }

            if (ImGui.CollapsingHeader("Memory Usage")) {
                ImGui.Text("Map Size: " + Voxel.MapSize);
                ImGui.Text("Map Max Levels: " + voxel.levels);
                ImGui.Text("Using Sparse Textures?: " + Voxel.SparseTextures);
                ImGui.Text("Map Memory Usage (theoretical): " + (voxel.memoryUsage / (1024)) + "kb");
                ImGui.Text("Actual Map Memory Usage (if sparse): " + ((voxel.memoryUsage - voxel.memoryUsageSparseReclaimed) / (1024)) + "kb");


                ImGui.Text("Sparse Reclaimed Memory Per Level");
                ImGui.BeginChild("Scrolling");
                for (int i = 0; i < voxel.levels; i++) {
                    ImGui.Text($"{i}: {voxel.memoryUsageSparseReclaimedPerLevel[i] / 1024}kb");
                }

                ImGui.EndChild();
            }

            if (ImGui.CollapsingHeader("Colors & Lighting")) {
                System.Numerics.Vector3 dir = ToVec3(lightDirection);
                ImGui.SliderFloat3("Sun direction", ref dir, -1f, 1f);
                FromVec3(dir, ref lightDirection);

                System.Numerics.Vector3 color = ToVec3(topColor);
                ImGui.ColorPicker3("Top Color", ref color);
                FromVec3(color, ref topColor);

                color = ToVec3(sideColor);
                ImGui.ColorPicker3("Side Color", ref color);
                FromVec3(color, ref sideColor);

                ImGui.SliderFloat("Ambient Strength", ref ambientStrength, 0.0f, 1.0f);
                ImGui.SliderFloat("Normals Strength", ref normalMapStrength, 0.0f, 1.0f);
                ImGui.SliderFloat("Roughness Strength", ref roughnessStrength, 0.0f, 1.0f);
                ImGui.SliderFloat("Metallic Strength", ref metallicStrength, 0.0f, 1.0f);
            }

            ImGui.End();            
        }

        protected override void OnRenderFrame(FrameEventArgs args) {
            base.OnRenderFrame(args);
            frameCount += 1;
            float delta = (float)args.Time;
            frameGraphData[frameCount % 512] = delta;

            lightDirection = new Vector3(MathF.Sin(timeElapsed * 0.01f), 0.6f, MathF.Cos(timeElapsed * 0.01f)).Normalized();


            skybox.Update(timeElapsed, lightDirection);

            controller.Update(this, delta);
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);
            GL.ClearColor(new Color4(0, 32, 48, 255));
            GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit | ClearBufferMask.StencilBufferBit);

            // Player movement and matrices
            if (CursorState == CursorState.Grabbed) {
                movement.Move(MouseState, KeyboardState, delta);
            }
            
            
            // Fullscreen toggle 
            if (KeyboardState.IsKeyPressed(Keys.F5)) {
                WindowState = 3 - WindowState;
            }
            
            // Cursor toggle
            if (KeyboardState.IsKeyPressed(Keys.F4)) {
                CursorState = 2 - CursorState;
            }
                
            if (KeyboardState.IsKeyPressed(Keys.F1)) {
                holdTemporalValues = !holdTemporalValues;
            }

            int readDepth;
            int writeDepth;

            if ((frameCount % 2) == 0) {
                readDepth = depthTex0;
                writeDepth = depthTex1;
            } else {
                readDepth = depthTex1;
                writeDepth = depthTex0;
            }

            int scaleDown = 1 << scaleDownFactor;
            int x = (int)MathF.Ceiling((float)(ClientSize.X / scaleDown) / 32.0f);
            int y = (int)MathF.Ceiling((float)(ClientSize.Y / scaleDown) / 32.0f);


            // Run the depth downscaler / pyramid thingy
            GL.UseProgram(depthStuff.program);
            GL.BindImageTexture(0, readDepth, 0, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R32f);
            GL.BindImageTexture(1, depthTex2, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.R32f);
            GL.DispatchCompute(x / 2 + 1, y / 2 + 1, 1);

            // Bind compute shader and execute it
            GL.UseProgram(compute.program);
            movement.UpdateMatrices((float)(ClientSize.Y / scaleDown) / (float)(ClientSize.X / scaleDown), useTemporalReproOpt);
            GL.Uniform2(1, ClientSize.ToVector2() / scaleDown);
            GL.UniformMatrix4(2, true, ref movement.viewMatrix);
            GL.UniformMatrix4(3, true, ref movement.projMatrix);
            GL.Uniform3(4, movement.position);
            GL.Uniform1(5, maxLevelIter);
            GL.Uniform1(6, maxIter);
            GL.Uniform1(7, Voxel.MapSize);
            GL.Uniform1(8, debugView);
            GL.Uniform1(9, maxReflections);
            GL.Uniform1(10, useSubVoxels ? 1 : 0);
            GL.Uniform1(11, reflectionRoughness);
            GL.Uniform3(12, lightDirection.Normalized());
            GL.Uniform1(13, useMipchainCacheOpt ? 1 : 0);
            GL.Uniform1(14, useAABBOpt ? 1 : 0);
            GL.Uniform1(15, maxSubVoxelIter);
            GL.UniformMatrix4(16, true, ref lastFrameViewMatrix);
            GL.Uniform1(17, 0);
            GL.Uniform1(18, useTemporalReproOpt ? 1 : 0);
            GL.Uniform3(19, lastPosition);
            GL.Uniform1(20, ambientStrength);
            GL.Uniform1(21, normalMapStrength);
            GL.Uniform1(22, roughnessStrength);
            GL.Uniform1(23, metallicStrength);
            GL.Uniform3(24, topColor);
            GL.Uniform3(25, sideColor);
            GL.Uniform1(26, holdTemporalValues ? 1 : 0);
            GL.Uniform1(27, (float)scaleDown);
            GL.Uniform1(28, usePositionalTemporalReproOpt ? 1 : 0);
            GL.Uniform1(30, maxShadowIter);
            GL.Uniform1(40, maxReproIter);

            GL.BindImageTexture(0, screenTexture, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rgba8);
            GL.BindImageTexture(1, writeDepth, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.R32f);
            GL.BindTextureUnit(2, voxel.texture);
            GL.BindTextureUnit(3, skybox.texture);
            GL.BindTextureUnit(4, voxel.sparseHelper);
            GL.BindTextureUnit(5, depthTex2);
            
            GL.DispatchCompute(x, y, 1);
            GL.BlitNamedFramebuffer(fbo, 0, 0, 0, ClientSize.X / scaleDown, ClientSize.Y / scaleDown, 0, 0, ClientSize.X, ClientSize.Y, ClearBufferMask.ColorBufferBit, BlitFramebufferFilter.Nearest);

            if (!holdTemporalValues) {
                lastFrameViewMatrix = movement.viewMatrix;
                lastPosition = movement.position;
            }

            ImGuiDebug(delta);
            controller.Render();

            // Screenshotting
            if (KeyboardState.IsKeyPressed(Keys.F3)) {
                Screenshot();
            }

            ImGuiController.CheckGLError("End of frame");
            SwapBuffers();
            timeElapsed += delta;
        }
    }
}
