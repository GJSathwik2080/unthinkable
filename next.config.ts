import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  turbopack: { root: __dirname },
  distDir: ".build",
  allowedDevOrigins: ["172.20.181.82"],
};

export default nextConfig;
