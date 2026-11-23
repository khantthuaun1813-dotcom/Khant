// Cloudflare Worker: serves the original Lua file from GitHub.
// Expected loader request: POST / with body key_path=1.lua

const REPO_OWNER = "khantthuaun1813-dotcom";
const REPO_NAME = "Khant";
const BRANCH = "main";
const LUA_FILENAME = "1.lua";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

function reply(message, status = 200) {
  return new Response(message, {
    status,
    headers: {
      ...CORS,
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store"
    }
  });
}

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    let filename;

    if (request.method === "POST") {
      try {
        const formBody = await request.text();
        filename = new URLSearchParams(formBody).get("key_path");
      } catch {
        return reply("Invalid request", 400);
      }
    } else if (request.method === "GET") {
      filename = url.pathname.replace(/^\/+/, "");
    } else {
      return reply("Method not allowed", 405);
    }

    if (filename !== LUA_FILENAME) {
      return reply("Not found", 404);
    }

    const githubRawUrl = `https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${LUA_FILENAME}`;

    try {
      const upstream = await fetch(githubRawUrl);
      if (!upstream.ok) {
        return reply(`GitHub fetch failed (${upstream.status})`, 502);
      }

      // Preserve binary Lua bytes without text decoding/re-encoding.
      return new Response(upstream.body, {
        status: 200,
        headers: {
          ...CORS,
          "Content-Type": "application/octet-stream",
          "Cache-Control": "no-store"
        }
      });
    } catch {
      return reply("GitHub connection failed", 502);
    }
  }
};