# Github CI/CD

## Dependencies

### Github

- [actions/checkout@v4](https://github.com/actions/checkout)

### Docker

- [docker/setup-qemu-action@v3](https://github.com/docker/setup-qemu-action)
- [docker/setup-buildx-action@v3](https://github.com/docker/setup-buildx-action)
- [docker/login-action@v3](https://github.com/docker/login-action)

### Others

- [ludeeus/action-shellcheck@master](https://github.com/ludeeus/action-shellcheck)
- [hadolint/hadolint-action@v3.1.0](https://github.com/hadolint/hadolint-action)

## Runners

- `ubuntu-latest` (public repository): 4 CPU - 16GB RAM - 14 GB SSD
- `ubuntu-latest` (private repository): 2 CPU - 7GB RAM - 14 GB SSD

[Source: Github](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners#standard-github-hosted-runners-for--private-repositories)

## Workflows

<details>
  <summary>Pull Request</summary>

  ```mermaid
    graph LR
      A[pull_request] --> B[lint_shell]
      A --> C[lint_dockerfile]
      B --> D[Run ShellCheck]
      C --> E[Run Hadolint]
      A --> F[docker_dry_build]
      F --> G[Checkout repository]
      F --> H[Install jq]
      F --> I[Get the latest PrestaShop version]
      F --> J[Should give the 'latest' tag for the latest version available]
      F --> K[Should not give the 'latest' tag to 8.1.2]
      F --> L[Should not give the 'latest' tag if PHP version is not recommended]
      A --> M[docker_build]
      M --> N[Checkout repository]
      M --> O[Call the docker build chain]
      M --> P[Test the image with a dry run]
      M --> Q[Test the image tooling composer]
      M --> R[Test the image tooling phpunit]
      M --> S[Test the image tooling phpstan]
      M --> T[Test the image tooling xdebug]
      A --> U[docker_build_old_php]
      U --> V[Checkout repository]
      U --> W[Call the docker build chain]
      U --> X[Test the image with a dry run]
      A --> Y[docker_build_debian]
      Y --> Z[Checkout repository]
      Y --> AA[Call the docker build chain]
      Y --> AB[Test the image with a dry run]
      Y --> AC[The image has a PrestaShop console CLI]
      A --> AD[docker_build_nightly]
      AD --> AE[Checkout repository]
      AD --> AF[Call the docker build chain]
      A --> AG[docker_build_cross_compile]
      AG --> AH[Checkout repository]
      AG --> AI[Set up QEMU]
      AG --> AJ[Set up Docker Buildx]
      AG --> AK[Test the docker build chain while cross compiling to aarch64]
  ```
</details>

<details>
  <summary>Docker Base Publish</summary>

  ```mermaid
  graph TD
    A[workflow_dispatch] -->|inputs| B[build_and_publish]
    B --> C[Checkout repository]
    B --> D[Set up QEMU]
    B --> E[Set up Docker Buildx]
    B --> F[Login to Docker Hub]
    B --> G[Build and push base image]
  ```
</details>

<details>
  <summary>Docker Publish</summary>

  ```mermaid
  graph TD
    A[workflow_dispatch] -->|inputs| B[build_and_publish]
    B --> C[Checkout repository]
    B --> D[Set up QEMU]
    B --> E[Set up Docker Buildx]
    B --> F[Login to Docker Hub]
    B --> G[Build and push image]
  ```
</details>

<details>
  <summary>Nightly Cron Publish</summary>

  ```mermaid
  graph TD
  A[workflow_dispatch] -->|inputs| B[build_and_publish]
  B --> C[Checkout repository]
  B --> D[Set up QEMU]
  B --> E[Set up Docker Buildx]
  B --> F[Login to Docker Hub]
  B --> G[Build and push the nightly]
  ```
</details>
