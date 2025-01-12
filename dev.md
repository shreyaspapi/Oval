# Developer Documentation

## Prerequisites

To work on this Electron project, you must have the following installed:

- **Conda**: A package, dependency, and environment management tool.
- **conda-pack**: To pack Conda environments into tarballs.
- **conda-lock**: To generate lockfiles for Conda environments.

Ensure these tools are properly installed and configured before proceeding.

---

## Getting Started

1. **Clone the repository**:

    ```bash
    git clone https://github.com/open-webui/app
    cd app
    ```

2. **Install Node.js dependencies**:

    ```bash
    npm i
    ```

3. **Generate the Python environment tarball**:

    ```bash
    npm run create:python-tar
    ```

4. **Start the development environment**:

    ```bash
    npm run start
    ```

    This will launch the project in development mode.

---

## Building Distributables

To generate production-ready distributables (e.g., installers or app packages), run:

```bash
npm run make
```

This will create the necessary files for distribution in the `out` directory.

---

## Notes

- Make sure you have the required versions of **conda**, **conda-pack**, and **conda-lock** to avoid compatibility issues.
- If you encounter any issues, check the project-specific scripts in the `package.json` file.

Enjoy developing! 🚀
