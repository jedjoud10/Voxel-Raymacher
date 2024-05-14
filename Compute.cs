using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using static System.Net.Mime.MediaTypeNames;

namespace Test123Bruh {
    internal class Compute {
        public int program;
        public Compute(string path) {
            string source = ReadSource(path);
            int temp = GL.CreateShader(ShaderType.ComputeShader);
            GL.ShaderSource(temp, source);
            GL.CompileShader(temp);
            program = GL.CreateProgram();
            GL.AttachShader(program, temp);
            GL.LinkProgram(program);

            string shaderLog = GL.GetShaderInfoLog(temp);
            string programLog = GL.GetProgramInfoLog(program);

            if (shaderLog != "") {
                throw new Exception(shaderLog);
            }

            if (programLog != "") {
                throw new Exception(programLog);
            }

            GL.ValidateProgram(program);
        }  

        private static string ReadSource(string path) {
            string source = File.ReadAllText(Path.Combine(GetResourceDir(), path));
            source = Preprocess(source);
            return source;
        }

        private static string GetResourceDir() {
            string execPath = System.Reflection.Assembly.GetEntryAssembly().Location;
            execPath = Path.GetDirectoryName(execPath);
            string global = Path.Combine(execPath, "Resources");
            return global;
        }

        private static string Preprocess(string input) {
            string output = "";
            using (StringReader sr = new StringReader(input)) {
                string line;
                while ((line = sr.ReadLine()) != null) {
                    if (line.StartsWith("#include")) {
                        string[] args = line.Split(" ");
                        string name = args[1];
                        output += "\n" + ReadSource(name);
                    } else {
                        output += "\n" + line;
                    }
                }
            }


            return output;
        }
    }
}
