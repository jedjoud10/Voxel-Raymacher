using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Voxel {
        public int texture;
        public int sparseHelper;
        public const bool SparseTextures = true;
        public const bool ListSparsePages = false;
        public const int MapSize = 64;
        public const SizedInternalFormat Format = SizedInternalFormat.Rgba32ui;
        public int levels;
        public ulong memoryUsage = 0;
        public ulong memoryUsageSparseReclaimed = 0;
        public ulong[] memoryUsageSparseReclaimedPerLevel;
        Compute generation;
        Compute propagate;

        /* Memory Optimizations:
         * Sparse textures (DONE)
         * Maybe lossless compression
         * 
         * Speed optimizations:
         * Optimize iteration using subgroup shenanigans?
         * Temporal depth reprojection from last frame (use it as "starting point" for iter) (DONE, but buggy. Also only works with rotational repr rn)
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
            Vector3i[] sizes = GetPageSizesFor3DFormat(Format);
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
            if (SparseTextures && ListSparsePages) {
                var vals = Enum.GetValues(typeof(SizedInternalFormat));
                foreach (var item in vals) {
                    Console.WriteLine(GetPageSizesFor3DFormat((SizedInternalFormat)item));
                }
            }
            

            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            int pageSize = -1;

            if (SparseTextures) {
                pageSize = DoSparseStuff();
            }

            levels = Int32.Log2(MapSize);

            if (SparseTextures) {
                levels -= Int32.Log2(pageSize)-1;
            }

            memoryUsageSparseReclaimedPerLevel = new ulong[levels];

            GL.TextureStorage3D(texture, levels, Format, MapSize, MapSize, MapSize);
            GL.Ext.TexturePageCommitment(texture, 0, 0, 0, 0, MapSize, MapSize, MapSize, true);
            GL.GetInternalformat(ImageTarget.Texture3D, Format, InternalFormatParameter.ImageTexelSize, 1, out int pixelSize);
            Console.WriteLine($"Pixel Size (bytes): " + pixelSize);

            ulong memCalcSize = (ulong)MapSize;
            for (int i = 0; i < levels; i++) {
                memoryUsage += memCalcSize * memCalcSize * memCalcSize * (ulong)pixelSize;
                memCalcSize /= 2;
                memCalcSize = Math.Max(memCalcSize, 1);
            }

            generation = new Compute("Voxel.glsl");
            propagate = new Compute("VoxelPropagate.glsl");
            
            GL.UseProgram(generation.program);
            GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.WriteOnly, Format);
            GL.DispatchCompute(MapSize / 4, MapSize / 4, MapSize / 4);

            sparseHelper = -1;
            if (SparseTextures) {
                sparseHelper = GL.GenTexture();
                int totalPagesSize = MapSize / pageSize;
                GL.BindTexture(TextureTarget.Texture3D, sparseHelper);
                GL.TextureStorage3D(sparseHelper, levels, SizedInternalFormat.R32i, totalPagesSize, totalPagesSize, totalPagesSize);
            }

            int testSize = MapSize;
            GL.UseProgram(propagate.program);
            GL.Uniform1(4, pageSize);
            List<(Vector3i, int)> toUncommit = new List<(Vector3i, int)>();
            for (int i = 0; i < levels-1; i++) {
                testSize /= 2;
                testSize = Math.Max(testSize, 1);

                if (SparseTextures) {
                    // commit next level since we will be writing to it
                    GL.Ext.TexturePageCommitment(texture, i + 1, 0, 0, 0, testSize, testSize, testSize, true);

                    // needed for readback after the compute to get rid of unused pages
                    GL.BindImageTexture(2, sparseHelper, i, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.R32i);
                }

                GL.BindImageTexture(0, texture, i, false, 0, TextureAccess.ReadOnly, Format);
                GL.BindImageTexture(1, texture, i+1, false, 0, TextureAccess.WriteOnly, Format);

                GL.Uniform1(3, (i != 0) ? 1 : 0);

                int dispatches = (int)MathF.Ceiling((float)testSize / 4.0f);
                GL.DispatchCompute(dispatches, dispatches, dispatches);
                Console.WriteLine($"Dispatch, R: {i}, W: {i + 1}");
                GL.MemoryBarrier(MemoryBarrierFlags.ShaderImageAccessBarrierBit);
                //GL.Finish();

                if (SparseTextures) {
                    int testtest = testSize * 2;
                    int totalPagesSize = testtest / pageSize;
                    int[] readbackData = new int[totalPagesSize * totalPagesSize * totalPagesSize];
                    GL.GetTextureSubImage(sparseHelper, i, 0, 0, 0, totalPagesSize, totalPagesSize, totalPagesSize, PixelFormat.RedInteger, PixelType.Int, readbackData.Length * 4, readbackData);

                    static (int,int,int) IndexToPos(int index, int size) {
                        int index2 = index;

                        // N(ABC) -> N(A) x N(BC)
                        int y = index2 / (size * size);   // x in N(A)
                        int w = index2 % (size * size);  // w in N(BC)

                        // N(BC) -> N(B) x N(C)
                        int z = w / size;        // y in N(B)
                        int x = w % size;        // z in N(C)
                        return (x, y, z);
                    }

                    Console.WriteLine($"Uncommit {i}");
                    for (int j = 0; j < readbackData.Length; j++) {
                        (int pageX, int pageZ, int pageY) = IndexToPos(j, totalPagesSize);

                        //Console.WriteLine($"{pageX}, {pageY}, {pageZ}, act = {readbackData[j]}");
                        int val = readbackData[j];
                        if (val == 4096) {
                            toUncommit.Add((new Vector3i(pageX, pageY, pageZ), i));
                            ulong reclaimed = (ulong)(pixelSize * pageSize * pageSize * pageSize);
                            memoryUsageSparseReclaimed += reclaimed;
                            memoryUsageSparseReclaimedPerLevel[i] += reclaimed;
                        }
                    }


                    //GL.Finish();
                }
            }

            foreach (var item in toUncommit) {
                (var page, var i) = item;
                GL.Ext.TexturePageCommitment(texture, i, page.X * pageSize, page.Y * pageSize, page.Z * pageSize, pageSize, pageSize, pageSize, false);
            }

        }
    }
}
