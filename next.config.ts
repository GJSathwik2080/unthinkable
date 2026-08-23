import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Removed distDir: ".build" for Vercel compatibility
  // Removed hardcoded allowedDevOrigins which is not needed for prod
};

export default nextConfig;
