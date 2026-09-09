import {
  AuthIncarnationScopeV2,
  PendingAuthIncarnationBindingV2,
  parseAuthIncarnationScopeV2,
  parsePendingAuthIncarnationBindingV2,
} from "./auth_incarnation_v2";

export interface TrustedAccountGenerationIssueRequestV2 {
  scope: AuthIncarnationScopeV2;
  reauthAfterSecV2: number;
}

/**
 * Trust boundary for a future provider-authenticated creation/enrollment
 * operation. Implementations must not be reachable from ordinary callables,
 * stale ID tokens, or a forced-refresh path.
 */
export interface TrustedAccountGenerationIssuerV2 {
  issuePendingBinding(
    request: TrustedAccountGenerationIssueRequestV2,
  ): Promise<PendingAuthIncarnationBindingV2>;
}

export class TrustedIssuerUnavailableErrorV2 extends Error {
  constructor() {
    super("The trusted Auth incarnation V2 issuer is not available.");
    this.name = "TrustedIssuerUnavailableErrorV2";
  }
}

class UnavailableTrustedAccountGenerationIssuerV2
implements TrustedAccountGenerationIssuerV2 {
  async issuePendingBinding(
    request: TrustedAccountGenerationIssueRequestV2,
  ): Promise<PendingAuthIncarnationBindingV2> {
    // Validate even on the closed path so callers cannot use this seam as a
    // permissive parser. No production implementation is supplied here.
    parseAuthIncarnationScopeV2(request.scope);
    throw new TrustedIssuerUnavailableErrorV2();
  }
}

export const unavailableTrustedAccountGenerationIssuerV2:
TrustedAccountGenerationIssuerV2 = Object.freeze(
  new UnavailableTrustedAccountGenerationIssuerV2(),
);

/** Test-support validator for injected fakes; it performs no issuance. */
export function validatePendingIssuerResultV2(
  value: unknown,
): PendingAuthIncarnationBindingV2 {
  return parsePendingAuthIncarnationBindingV2(value);
}
