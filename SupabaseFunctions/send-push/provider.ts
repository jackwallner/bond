// The APNs provider token. Apple rejects one older than an hour and refuses a
// key whose token changes too often, and a new function instance would mint its
// own, so the token is shared through the database (0019) and reused for 50
// minutes. Before 0019 is applied the shared store is missing and each instance
// keeps its own, as before.

export interface StoredToken {
  token: string;
  issuedAt: number;
}

export interface TokenStore {
  load(): Promise<StoredToken | null>;
  save(token: StoredToken): Promise<void>;
}

const REUSE_SECONDS = 50 * 60;

export class ProviderTokens {
  private cached: StoredToken | null = null;

  constructor(
    private readonly mint: (issuedAt: number) => Promise<string>,
    private readonly store: TokenStore,
  ) {}

  async get(nowSeconds: number): Promise<string> {
    if (this.fresh(this.cached, nowSeconds)) return this.cached!.token;
    const shared = await this.store.load().catch(() => null);
    if (this.fresh(shared, nowSeconds)) {
      this.cached = shared;
      return shared!.token;
    }
    const minted = { token: await this.mint(nowSeconds), issuedAt: nowSeconds };
    this.cached = minted;
    await this.store.save(minted).catch(() => {});
    return minted.token;
  }

  /// APNs refused it: the next run mints a new one rather than reuse it.
  async drop(): Promise<void> {
    this.cached = null;
    await this.store.save({ token: "", issuedAt: 0 }).catch(() => {});
  }

  private fresh(token: StoredToken | null, nowSeconds: number): boolean {
    return !!token && token.token.length > 0 && nowSeconds - token.issuedAt >= 0 &&
      nowSeconds - token.issuedAt < REUSE_SECONDS;
  }
}
