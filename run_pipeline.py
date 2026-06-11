import subprocess
import os
import sys

# Ensure standard output can handle Unicode emojis on Windows console
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Git absolute path found on system
GIT_PATH = r"C:\Program Files\Git\cmd\git.exe"


def run_command(cmd_args):
    result = subprocess.run(cmd_args, capture_output=True, text=True, encoding='utf-8')
    return result.returncode, result.stdout, result.stderr

def main():
    print("=== STARTING INGRESS EVENT PIPELINE ===")
    
    # 1. Run Scraper
    print("Running scraper.py...")
    ret, stdout, stderr = run_command([sys.executable, "scraper.py"])
    print(stdout)
    if stderr:
        print(f"Scraper errors/warnings:\n{stderr}")
        
    if ret != 0:
        print("PIPELINE_ERROR: Scraper script failed.")
        sys.exit(1)
        
    # 2. Check for new articles
    if not os.path.exists("new_articles.json"):
        print("PIPELINE_COMPLETE: Database is up-to-date. No new articles to parse.")
        sys.exit(0)
        
    # 3. New articles exist, signal Antigravity to parse
    print("PIPELINE_PENDING_PARSING: New articles were found and written to new_articles.json.")
    print("\n--- INSTRUCTIONS FOR ANTIGRAVITY ---")
    print("1. Read 'new_articles.json' to see the scraped articles and their content.")
    print("2. Parse the dates, event names, and core gameplay changes (mutations) for each article.")
    print("3. Append the parsed events in the correct schema to 'events.json'.")
    print("4. Delete 'new_articles.json'.")
    print("5. Run the following Git commands to commit and push the updated database:")
    print(f'   & "{GIT_PATH}" add events.json')
    print(f'   & "{GIT_PATH}" commit -m "System: Update events database"')
    print(f'   & "{GIT_PATH}" push origin main')
    print("-------------------------------------")

if __name__ == "__main__":
    main()
