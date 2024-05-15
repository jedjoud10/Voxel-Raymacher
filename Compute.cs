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
            List<string> deps = new List<string>();
            string source = ReadSource(path, ref deps);
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

        private static string ReadSource(string path, ref List<string> deps) {
            string source = File.ReadAllText(Path.Combine(GetResourceDir(), path));
            source = Preprocess(source, ref deps);
            return source;
        }

        private static string GetResourceDir() {
            string execPath = System.Reflection.Assembly.GetEntryAssembly().Location;
            execPath = Path.GetDirectoryName(execPath);
            execPath = AppDomain.CurrentDomain.BaseDirectory;
            string global = Path.Combine(execPath, "Resources");
            return global;
        }

        private static string Preprocess(string input, ref List<string> deps) {
            string output = "";
            using (StringReader sr = new StringReader(input)) {
                string line;
                while ((line = sr.ReadLine()) != null) {
                    if (line.StartsWith("#include")) {
                        string[] args = line.Split(" ");
                        string name = args[1];

                        if (!deps.Contains(name)) {
                            output += "\n" + ReadSource(name, ref deps);
                            deps.Add(name);
                        } else {
                            output += "\n";
                        }
                    } else {
                        output += "\n" + line;
                    }
                }
            }


            return output;
        }
    }
}
