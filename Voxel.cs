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
        public int texture;
        public static int size = 128;
        public static int levels = Math.Min(Int32.Log2(size), 7);
        public ulong memoryUsage = 0;
        public bool sparseTextures = false;
        Compute generation;
        Compute propagate;

        /* Memory Optimizations:
         * Sparse textures (WIP)
         * Maybe lossless compression
         * 
         * Speed optimizations:
         * Temporal depth reprojection from last frame (use it as "starting point" for iter) (WIP)
         * AABB tree for node sizes 1 and larger (DONE)
         * AABB Bounds for sub-voxels, pre-calculated for EVERY possible sub-voxel combination. At runtime would just fetch the bounds from a texture maybe?
            * Bounds are symmetric in someways so we don't need to store *all* information really. Could be really optimized
            * Since terrain is generally flat, we can split the 4x4x4 into 4 bounds of 4x4
            * 2 bits * 3 axis * 2 (min/max) = 12 bits for each bound
            * Each bound has 4x4 sub-voxels, so 2^16 combinations, 65536. 
            * 65536 * 12 bits each => 768kb
         * Run low-res "pre-render" thingy that will cache minimum required depths (using ray thickness or cone instead of ray)
         * Use bitwise stuff for acceleration levels (nah)
         * Keep history of local child indices of un-hit child to avoid retracing from the top (DONE)
        */

        static Vector3i[] GetPageSizesFor3DFormat(SizedInternalFormat format) {
            GL.GetInternalformat(ImageTarget.Texture3D, format, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.NumVirtualPageSizesArb, 1, out int indexCount);
            Vector3i[] sizes = new Vector3i[indexCount];

            if (indexCount == 0) {
                Console.WriteLine("So page sizes!");
                return null;
            }

            Console.WriteLine("Format!!: " + format);
            Console.WriteLine("Page format count: " + indexCount);
            for (int i = 0; i < indexCount; ++i) {
                int copied = i;
                GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeIndexArb, ref copied);

                GL.GetInternalformat(ImageTarget.Texture3D, format, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeXArb, 1, out int xSize);
                GL.GetInternalformat(ImageTarget.Texture3D, format, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeYArb, 1, out int ySize);
                GL.GetInternalformat(ImageTarget.Texture3D, format, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeZArb, 1, out int zSize);
                Console.WriteLine($"I: {i}, X: {xSize}, Y: {ySize}, Z: {zSize}");

                sizes[i] = new Vector3i(xSize, ySize, zSize);
            }

            return sizes;
        }

        static Vector3i DoSparseStuff() {
            int a = 1;
            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.TextureSparseArb, ref a);


            int bestIndex = 0;
            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeIndexArb, ref bestIndex);
            return GetPageSizesFor3DFormat(SizedInternalFormat.Rg32ui)[0];
        }

        public Voxel() {
            /*
            int sparse = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, sparse);
            */

            /*
            Console.WriteLine(GetPageSizesFor3DFormat(SizedInternalFormat.Rg32ui));
            Console.WriteLine(GetPageSizesFor3DFormat(SizedInternalFormat.R32ui));
            Console.WriteLine(GetPageSizesFor3DFormat(SizedInternalFormat.R8ui));
            */

            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            Vector3i pageSizes = default;
            
            if (sparseTextures)
                DoSparseStuff();

            Vector3i sizes = new Vector3i(size, size, size);
            GL.TextureStorage3D(texture, levels, SizedInternalFormat.Rg32ui, size, size, size);

            // Sparse textures not supported by renderdoc, so it'd be nice to be able to turn em off
            if (sparseTextures) {
                Console.WriteLine("Page size: " + pageSizes);
                GL.GetTexParameterI(TextureTarget.Texture3D, (GetTextureParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.NumSparseLevelsArb, out int numSparseLevels);
                Console.WriteLine("Num Sparse Levels: " + numSparseLevels);

                for (int i = 0; i < numSparseLevels; i++) {

                    if (Vector3i.ComponentMax(sizes, pageSizes) == sizes) {
                        Console.WriteLine("Level" + i, "Commited Size: " + sizes);
                        GL.Ext.TexturePageCommitment(texture, i, 0, 0, 0, sizes.X, sizes.Y, sizes.Z, true);
                    }

                    sizes /= 2;
                }
            }

            ulong memCalcSize = (ulong)size;
            for (int i = 0; i < levels; i++) {
                memoryUsage += memCalcSize * memCalcSize * memCalcSize * 4 * 2;
                memCalcSize /= 2;
                memCalcSize = Math.Max(memCalcSize, 1);
            }

            generation = new Compute("Voxel.glsl");
            propagate = new Compute("VoxelPropagate.glsl");
            
            GL.UseProgram(generation.program);
            GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rg32ui);
            GL.DispatchCompute(size / 4, size / 4, size / 4);
            

            int testSize = size;
            GL.UseProgram(propagate.program);
            for (int i = 0; i < levels-1; i++) {
                GL.BindImageTexture(0, texture, i, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.Rg32ui);
                GL.BindImageTexture(1, texture, i+1, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rg32ui);
                GL.Uniform1(2, (i != 0) ? 1 : 0);
                testSize /= 2;
                testSize = Math.Max(testSize, 1);

                int dispatches = (int)MathF.Ceiling((float)testSize / 4.0f);
                GL.DispatchCompute(dispatches, dispatches, dispatches);
                GL.MemoryBarrier(MemoryBarrierFlags.ShaderImageAccessBarrierBit);
            }
        }
    }
}
