# ArgoCD OIDC Credentials

This post-bootstrap Application owns only the `argocd/argocd-dex`
ExternalSecret. ArgoCD itself remains managed by root OpenTofu configuration.
The existing Secret name, key, and ArgoCD discovery label are preserved.

ESO CRDs must exist before this Application reconciles. Do not put this resource
in ArgoCD's initial Helm release: that would require ESO before ArgoCD can
bootstrap it. Kubernetes-admin access remains the recovery path during SSO
bootstrap.

For an existing cluster, follow
[the guarded ownership handoff](../../.agents/references/dex-secret-ownership.md)
before publishing this move from the external-secrets Application.
