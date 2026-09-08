export const AUTHORIZATION_SCHEMA_VERSION = 1;
export const PUBLIC_ASSOCIATION_ID = "jba";

export const roles = [
  "superAdmin",
  "admin",
  "statistician",
  "rep",
  "media",
  "press",
  "fan",
] as const;

export type Role = (typeof roles)[number];

export const capabilities = {
  associationRead: "association.read",
  associationManage: "association.manage",
  membersRead: "members.read",
  membersManage: "members.manage",
  invitesManage: "invites.manage",
  scheduleManage: "schedule.manage",
  teamsManage: "teams.manage",
  teamsRepresent: "teams.represent",
  postsCreate: "posts.create",
  postsManage: "posts.manage",
  postsInternalRead: "posts.internal.read",
  postsAcknowledge: "posts.acknowledge",
  statsEnter: "stats.enter",
  statsApprove: "stats.approve",
  statsExport: "stats.export",
  pressRead: "press.read",
} as const;

const allCapabilities = Object.values(capabilities);

const roleCapabilities: Record<Role, readonly string[]> = {
  superAdmin: allCapabilities,
  admin: [
    capabilities.associationRead,
    capabilities.teamsManage,
    capabilities.postsCreate,
    capabilities.postsManage,
    capabilities.postsInternalRead,
    capabilities.statsEnter,
    capabilities.statsApprove,
    capabilities.statsExport,
    capabilities.pressRead,
  ],
  statistician: [
    capabilities.associationRead,
    capabilities.postsInternalRead,
    capabilities.statsEnter,
  ],
  rep: [
    capabilities.associationRead,
    capabilities.teamsRepresent,
    capabilities.postsCreate,
    capabilities.postsInternalRead,
    capabilities.postsAcknowledge,
  ],
  media: [
    capabilities.associationRead,
    capabilities.postsInternalRead,
    capabilities.statsExport,
    capabilities.pressRead,
  ],
  press: [
    capabilities.associationRead,
    capabilities.postsInternalRead,
    capabilities.statsExport,
    capabilities.pressRead,
  ],
  fan: [capabilities.associationRead],
};

export function isRole(value: unknown): value is Role {
  return typeof value === "string" && (roles as readonly string[]).includes(value);
}

export function capabilitiesForRole(role: Role): string[] {
  return [...roleCapabilities[role]];
}

export function canGrantRole(inviterRole: Role, requestedRole: Role): boolean {
  return inviterRole === "superAdmin" && requestedRole !== "superAdmin" && requestedRole !== "fan";
}
