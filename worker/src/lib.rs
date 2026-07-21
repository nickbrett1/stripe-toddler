use worker::*;

#[event(fetch)]
pub async fn main(req: Request, env: Env, ctx: Context) -> Result<Response> {
    Response::ok("Hello from Stripe Toddler Worker!")
}
