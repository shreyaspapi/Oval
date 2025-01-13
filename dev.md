# Developer Documentation
## Prerequisites
To work on this Electron project, you must have the following installed:
- **Conda**: A package, dependency, and environment management tool.
- **conda-pack**: To pack Conda environments into tarballs.
- **conda-lock**: To generate lockfiles for Conda environments.
- **Node.js 22+**: Ensure that your Node.js version is at least 22 (tested with v22.10).

### Installation Notes
- Install **conda-pack** and **conda-lock** globally or ensure they are available in the project's Python environment (e.g., a virtual environment).
- Double-check your tool versions to avoid compatibility issues.

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
    > Note: This requires **conda-lock** to be installed and properly configured.

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
- Ensure **conda**, **conda-pack**, and **conda-lock** are installed and working within your environment (global or virtual).
- Use Node.js **version 22+** to avoid runtime and compatibility issues (verified with v22.10).
- If you encounter issues, examine the project-specific scripts in the `package.json` file for troubleshooting.
- Always review logs carefully if commands produce errors to identify dependencies or configuration steps you might need to address.

Enjoy developing! 🚀