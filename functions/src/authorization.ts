import authorizationSchema from "./authorization_schema_v1.json";

export const AUTHORIZATION_SCHEMA_VERSION = authorizationSchema.schemaVersion;
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

const roleCapabilities = authorizationSchema.roles as Record<Role, readonly string[]>;

export function isRole(value: unknown): value is Role {
  return typeof value === "string" && (roles as readonly string[]).includes(value);
}

export function capabilitiesForRole(role: Role): string[] {
  return [...roleCapabilities[role]];
}

export function canGrantRole(inviterRole: Role, requestedRole: Role): boolean {
  return inviterRole === "superAdmin" && requestedRole !== "superAdmin" && requestedRole !== "fan";
}
