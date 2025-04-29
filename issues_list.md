# serve_config

A lightweight JSON configuration server built with Flask and deployed via Docker, Terraform, and Ansible.

Issues list

**High Priority**  
1. **Secrets management**  
   - **Issue:** Proxmox API token is hard-coded in `terraform/set-proxmox-env.sh` and tracked in Git.  
   - **Action:** Remove it from version control, add the script to `.gitignore`, purge it from Git history, and load any future tokens via an external, git-ignored file or a secrets manager/env var.  

2. **Terraform state files in Git & `.gitignore`**  
   - **Issue:** You’re committing `terraform.tfstate.backup` (and may still track other `*.tfstate*` files).  
   - **Action:** Update `.gitignore` to include `*.tfstate*` and `terraform.lock.hcl`; delete all checked-in state files; migrate to a remote state backend.  

3. **Flask route redundancy**  
   - **Issue:** Separate handlers for each JSON file in `src/serve_config.py`—every new config needs its own route.  
   - **Action:** Replace with a single dynamic route (e.g. `/\<filename>.json`) that validates and serves any file in `config_files`.  

4. **Hard-coded values in Terraform**  
   - **Issue:** `clone.vm_id=9002`, `node_name="proxmox"`, storage IDs, SSH username/key path, etc., are all literals.  
   - **Action:** Parameterize via `variables.tf` and pass overrides in `terraform.tfvars` or via `TF_VAR_…` env vars. For SSH, pass the public key’s **content** as a variable.  

5. **Deploy script portability & robustness**  
   - **Issue:**  
     - Uses macOS-only `sed -i ''`.  
     - Fixed `sleep 90` before SSH.  
   - **Action:**  
     - Detect OS or switch to `sed -i` with fallback.  
     - Replace static sleeps with the existing SSH-retry loop.  

6. **Brittle Ansible inventory management**  
   - **Issue:** You `sed`-inject the VM’s IP into a static `ansible/inventory/hosts`.  
   - **Action:**  
     - Switch to a dynamic inventory (Terraform → INI/YAML).  
     - Or pass `--extra-vars "ansible_host=$IP"` to `ansible-playbook` and target that host directly—no in-place edits.  

**Medium Priority**  
7. **Relative paths in Ansible playbook**  
   - **Issue:** `app_source_dir: "../../src/"` breaks if you move files or run from elsewhere.  
   - **Action:** Use `{{ playbook_dir }}/../src` (or a top-level `project_root` var) so paths are always correct.  

8. **Unspecified Ansible collection dependencies**  
   - **Issue:** You call `community.docker.docker_image`/`docker_container` but never pin or install the `community.docker` collection.  
   - **Action:** Add `ansible/requirements.yml` listing `community.docker`, and run `ansible-galaxy collection install -r requirements.yml` in your bootstrap.  

9. **Docker config file handling**  
   - **Issue:** `COPY config_files/*.json` in the image forces a rebuild on every config change.  
   - **Action:** Mount `/opt/serve_config/config_files` from the host into the container via `volumes:` in your Ansible `docker_container` task. Remove the `COPY config_files/*.json` step.  

10. **Single-stage Docker build**  
    - **Issue:** Installing build dependencies (e.g. `curl`) in the final image bloats it.  
    - **Action:** Convert to a multi-stage Dockerfile—do all `apt-get`/`pip install` in a builder stage, then copy only the runtime artifacts into a slim final image.  

11. **Dependency management (`gunicorn`)**  
    - **Issue:** `gunicorn` is installed in the Dockerfile but missing from `src/requirements.txt`.  
    - **Action:** Add a pinned `gunicorn==…` line to `requirements.txt` so all dependencies live in one place.  

**Low Priority**  
12. **Docker image tagging**  
    - **Issue:** You always tag as `serve_config:latest`, which can obscure what’s running.  
    - **Action:** Consider tagging with a Git SHA or version number for clearer rollbacks and audits.  

13. **README.md is minimal**  
    - **Issue:** No instructions on prerequisites, secrets setup, or deploy workflow.  
    - **Action:** Expand it to cover:  
      - Prerequisites (Terraform, Ansible, Docker, Python)  
      - How/where to set Proxmox token  
      - `deploy.sh` usage (with and without `--nuke`)  
      - How to call the service endpoints.  

---



