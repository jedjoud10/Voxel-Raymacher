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
        public static int size = 256;
        public static int levels = Math.Min(Int32.Log2(size), 70);
        public static SizedInternalFormat format = SizedInternalFormat.Rgba32ui;
        public ulong memoryUsage = 0;
        public static bool sparseTextures = false;
        public static bool listSparsePageCounts = false;
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

            Console.WriteLine("Format!!: " + format);
            if (indexCount == 0) {
                Console.WriteLine("No page sizes!");
                return null;
            }

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

        static int DoSparseStuff() {
            int enable = 1;
            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.TextureSparseArb, ref enable);

            // try to find the index for a page size that is cubic sized (32x32x32)
            Vector3i[] sizes = GetPageSizesFor3DFormat(format);
            (var bestIndex, var bestPageSize) = sizes
                .AsEnumerable()
                .Select((vec,i) => (i,vec))
                .Where(data => data.vec.X == data.vec.Y && data.vec.Y == data.vec.Z)
                .OrderBy(data => data.vec.X)
                .FirstOrDefault();
            Console.WriteLine("Best page size for current format is: " + bestPageSize + " index: " + bestIndex);

            if (bestPageSize.X == 0) {
                throw new Exception("Could not find an appropiate sparse page size for the current format");
            }

            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeIndexArb, ref bestIndex);
            return bestPageSize.X;
        }


        public Voxel() {
            if (sparseTextures && listSparsePageCounts) {
                var vals = Enum.GetValues(typeof(SizedInternalFormat));
                foreach (var item in vals) {
                    Console.WriteLine(GetPageSizesFor3DFormat((SizedInternalFormat)item));
                }
            }
            

            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            int pageSize = -1;

            if (sparseTextures) {
                pageSize = DoSparseStuff();
            }

            int recursiveSize = size;
            //levels = 5;
            GL.TextureStorage3D(texture, levels, format, size, size, size);

            // Sparse textures not supported by renderdoc, so it'd be nice to be able to turn em off
            if (sparseTextures) {
                Console.WriteLine("Page size: " + pageSize);
                GL.GetTexParameterI(TextureTarget.Texture3D, (GetTextureParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.NumSparseLevelsArb, out int numSparseLevels);
                Console.WriteLine("Num Sparse Levels: " + numSparseLevels);

                // for some reason on my gpu the numSparseLevels value will always be 1 value too high, meaning that I cannot define the mip-chain tail as being fully resident
                // a lil hack around this would be to just make levels that will always have a size at least larger than the page size, and make a secondary texture that doesn't require sparse stuff

                for (int i = 0; i < numSparseLevels; i++) {

                    if (MathHelper.Max(recursiveSize, pageSize) == recursiveSize) {
                        Console.WriteLine($"Level {i}, Commited Size {recursiveSize}");
                        GL.Arb.TexPageCommitment(All.Texture3D, i, 0, 0, 0, recursiveSize, recursiveSize, recursiveSize, true);
                    }

                    recursiveSize /= 2;
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
            GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.WriteOnly, format);
            GL.DispatchCompute(size / 4, size / 4, size / 4);
            

            int testSize = size;
            GL.UseProgram(propagate.program);
            for (int i = 0; i < levels-1; i++) {
                GL.BindImageTexture(0, texture, i, false, 0, TextureAccess.ReadOnly, format);
                GL.BindImageTexture(1, texture, i+1, false, 0, TextureAccess.WriteOnly, format);
                GL.Uniform1(2, (i != 0) ? 1 : 0);
                testSize /= 2;
                testSize = Math.Max(testSize, 1);

                int dispatches = (int)MathF.Ceiling((float)testSize / 4.0f);
                GL.DispatchCompute(dispatches, dispatches, dispatches);
                GL.MemoryBarrier(MemoryBarrierFlags.ShaderImageAccessBarrierBit);

                /*
                if (sparseTextures) {
                    InternalRepr[] readbackData = new InternalRepr[testSize * testSize * testSize];
                    GL.GetTextureSubImage(texture, i + 1, 0, 0, 0, testSize, testSize, testSize, PixelFormat.RgInteger, PixelType.UnsignedInt, readbackData.Length, readbackData);
                }
                */
            }

        }

        struct InternalRepr {
            uint first;
            uint second;
        }
    }
}
