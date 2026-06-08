// identify-item — secure Gemini Flash vision proxy for WheresMy.
//
// The browser sends a photo (base64) + the logged-in user's auth token.
// This function:
//   1. Verifies the caller is a real signed-in user (not just the public key).
//   2. Calls Gemini with the GEMINI_API_KEY secret (never exposed to the client).
//   3. Returns a short item name: { "name": "blue water bottle" }
//
// Deploy:  supabase functions deploy identify-item --project-ref quclamokiadmbockaqnn
// Secret:  supabase secrets set GEMINI_API_KEY=...   --project-ref quclamokiadmbockaqnn

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MODEL = "gemini-2.5-flash";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Require a genuine logged-in user (the anon key alone is rejected).
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) {
      return json({ error: "Not authenticated" }, 401);
    }

    // 2. Read the image payload.
    const { image, mimeType } = await req.json().catch(() => ({}));
    if (!image) return json({ error: "No image provided" }, 400);

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "Server missing GEMINI_API_KEY" }, 500);

    const prompt =
      "You are naming the single main physical object in this photo so it can be logged " +
      "in a household inventory. Reply with ONLY the item name: up to 6 words, as specific " +
      "as the photo allows. Always include the object type (e.g. mug, book, bottle, charger), " +
      "and add the most useful distinguishing details you can actually see — colour, material, " +
      "and any clearly legible brand, title, or label text. If a book, product, or label shows " +
      "readable text, use it (e.g. 'Charlotte's Web book'). Do not invent details you cannot see. " +
      "No explanation, no quotes, no trailing punctuation. " +
      "Examples: black leather wallet | Indiana ceramic coffee mug | " +
      "Charlotte's Web paperback book | white Anker usb-c charger";

    // 3. Call Gemini.
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${geminiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{
            parts: [
              { text: prompt },
              { inline_data: { mime_type: mimeType || "image/jpeg", data: image } },
            ],
          }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 50 },
        }),
      },
    );

    if (!geminiRes.ok) {
      console.error("Gemini error:", geminiRes.status, await geminiRes.text());
      return json({ error: "Vision service error" }, 502);
    }

    const result = await geminiRes.json();
    const raw: string = result?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    const name = raw
      .trim()
      .replace(/^["']|["']$/g, "")
      .replace(/\s+/g, " ")
      .slice(0, 80);

    if (!name) return json({ error: "Could not identify item" }, 422);

    return json({ name });
  } catch (err) {
    console.error("Unexpected error:", err);
    return json({ error: "Unexpected error" }, 500);
  }
});
