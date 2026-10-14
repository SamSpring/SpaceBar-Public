"use strict";
const statusLine = document.querySelector("#release-status");
const download = document.querySelector("#download");
download.addEventListener("click", (event) => {
  if (download.getAttribute("href") === "#release-status") {
    event.preventDefault();
    statusLine.focus({ preventScroll: true });
    statusLine.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  }
});
function githubRepo(value) {
  return typeof value === "string" && /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value);
}
fetch("release.json").then(response => {
  if (!response.ok) throw new Error("Release configuration unavailable");
  return response.json();
}).then(release => {
  if (githubRepo(release.repositoryUrl)) {
    const source = document.createElement("a");
    source.href = release.repositoryUrl;
    source.textContent = "View source on GitHub";
    document.querySelector("#source-link").replaceChildren(source);
  }
  const expected = `${release.repositoryUrl}/releases/download/v${release.version}/SpaceBar-${release.version}-arm64.zip`;
  if (githubRepo(release.repositoryUrl) && release.downloadUrl === expected && release.notarized === true && release.cleanInstallVerified === true && release.architecture === "arm64" && release.minimumMacOS === "27.0" && /^[a-f0-9]{64}$/.test(release.sha256 || "") && /^\d+\.\d+\.\d+$/.test(release.version)) {
    download.href = release.downloadUrl;
    statusLine.textContent = `SpaceBar ${release.version} · Developer ID signed and notarized.`;
    const checksum = document.createElement("a");
    checksum.href = `${release.repositoryUrl}/releases/download/v${release.version}/SHA256SUMS.txt`;
    checksum.textContent = " Verify download";
    statusLine.append(checksum);
  }
}).catch(() => {
  // The verified release links remain available without JavaScript/config.
});

const demo = document.querySelector("#menu-demo");
const demoToggle = document.querySelector("#demo-toggle");
if (demo && demoToggle) {
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let userPaused = false;
  demo.muted = true;
  demo.defaultMuted = true;
  demo.autoplay = !reducedMotion.matches;
  demo.controls = false;
  demoToggle.hidden = false;
  const updateDemoButton = () => {
    demoToggle.textContent = demo.paused ? "Play demo" : "Pause demo";
  };
  demo.addEventListener("play", updateDemoButton);
  demo.addEventListener("pause", updateDemoButton);
  const startAutomatically = () => {
    if (!userPaused && !reducedMotion.matches) demo.play().catch(updateDemoButton);
  };
  demo.addEventListener("canplay", startAutomatically, { once: true });
  demoToggle.addEventListener("click", () => {
    userPaused = !demo.paused;
    demo.autoplay = !userPaused && !reducedMotion.matches;
    if (userPaused) demo.pause();
    else demo.play().catch(updateDemoButton);
  });
  reducedMotion.addEventListener("change", () => {
    demo.autoplay = !userPaused && !reducedMotion.matches;
    if (reducedMotion.matches) demo.pause();
    else startAutomatically();
  });
  startAutomatically();
}
