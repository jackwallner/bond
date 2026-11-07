import { assertEquals } from "jsr:@std/assert@1";
import { ProviderTokens, type StoredToken } from "./provider.ts";

function setup(shared: StoredToken | null) {
  const state = { shared, minted: 0 };
  const tokens = () =>
    new ProviderTokens(
      (issuedAt) => {
        state.minted += 1;
        return Promise.resolve(`jwt-${issuedAt}`);
      },
      {
        load: () => Promise.resolve(state.shared),
        save: (token) => {
          state.shared = token;
          return Promise.resolve();
        },
      },
    );
  return { state, tokens };
}

Deno.test("a new function instance reuses the token another one made", async () => {
  const { state, tokens } = setup({ token: "jwt-shared", issuedAt: 1000 });
  assertEquals(await tokens().get(1000 + 49 * 60), "jwt-shared");
  assertEquals(await tokens().get(1000 + 49 * 60), "jwt-shared");
  assertEquals(state.minted, 0);
});

Deno.test("an old token is replaced once, and shared", async () => {
  const { state, tokens } = setup({ token: "jwt-old", issuedAt: 1000 });
  const now = 1000 + 51 * 60;
  assertEquals(await tokens().get(now), `jwt-${now}`);
  assertEquals(await tokens().get(now + 60), `jwt-${now}`);
  assertEquals(state.minted, 1);
});

Deno.test("without the shared store each instance still works", async () => {
  let minted = 0;
  const tokens = new ProviderTokens(
    () => Promise.resolve(`jwt-${++minted}`),
    { load: () => Promise.reject(new Error("missing")), save: () => Promise.reject(new Error("missing")) },
  );
  assertEquals(await tokens.get(1000), "jwt-1");
  assertEquals(await tokens.get(1060), "jwt-1");
});

Deno.test("a refused token is not reused", async () => {
  const { state, tokens } = setup(null);
  const provider = tokens();
  await provider.get(1000);
  provider.drop();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(await tokens().get(1060), "jwt-1060");
  assertEquals(state.minted, 2);
});
