import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Required for @mysten/dapp-kit and wallet extensions that use browser APIs
  reactStrictMode: true,
};

export default nextConfig;
