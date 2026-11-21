export const dynamic = "force-dynamic";
export async function GET(): Promise<Response> { return Response.json({ status: "ready" }, { status: 200, headers: { "cache-control": "no-store" } }); }
