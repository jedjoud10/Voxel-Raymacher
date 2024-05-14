using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Voxel {
        int texture;
        public static int size = 512;
        public static int levels = Math.Min(Int32.Log2(size), 7);
        long[] handles;
        Compute generation;
        Compute propagate;

        public Voxel() {
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            GL.TextureStorage3D(texture, levels, SizedInternalFormat.Rg32ui, size, size, size);       
            
            /*
            int testSize = size;
            for (int i = 0; i < levels; i++) {
                //GL.TexImage3D(TextureTarget.Texture3D, i, PixelInternalFormat.R32ui, testSize, testSize, testSize, 0, PixelFormat.RedInteger, PixelType.UnsignedInt, 0);
                //GL.GetTextureLevelParameter(texture, i, GetTextureParameter.TextureCompressedImageSize, out int imgSize);
                //GL.CompressedTexImage3D(TextureTarget.Texture3D, i, InternalFormat.CompressedRg, testSize, testSize, testSize, 0, imgSize, 0);
                
                testSize /= 2;
                testSize = Math.Max(testSize, 1);
            }
            */


            generation = new Compute("Voxel.glsl");
            propagate = new Compute("VoxelPropagate.glsl");


            handles = new long[levels];
            for (int i = 0; i < levels; i++) {
                handles[i] = GL.Arb.GetImageHandle(texture, i, false, 0, (PixelFormat)SizedInternalFormat.Rg32ui);
                GL.Arb.MakeImageHandleResident(handles[i], All.ReadWrite);
            }

            GL.UseProgram(generation.program);      
            GL.Arb.UniformHandle(0, handles[0]);
            GL.DispatchCompute(size / 4, size / 4, size / 4);

            int testSize = size;
            for (int i = 0; i < levels-1; i++) {
                GL.UseProgram(propagate.program);
                GL.Arb.UniformHandle(0, handles[i]);
                GL.Arb.UniformHandle(1, handles[i+1]);
                testSize /= 2;
                testSize = Math.Max(testSize, 1);

                int dispatches = (int)MathF.Ceiling((float)testSize / 4.0f);
                GL.DispatchCompute(dispatches, dispatches, dispatches);
            }
        }

        public void Bind(int program) {
            GL.Arb.UniformHandle(10, handles.Length, handles);
        }

        public void Update(float timePassed) {
            /*
            GL.UseProgram(generation.program);
            GL.Uniform1(0, timePassed);
            GL.Arb.UniformHandle(1, handles.Length, handles);
            GL.DispatchCompute(size / 4, size / 4, size / 4);
            */
        }
    }
}
