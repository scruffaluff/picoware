const button = document.getElementById("button");
const input = document.getElementById("input");
const output = document.getElementById("output");

button.addEventListener("click", async (event) => {
  const response = await fetch("wry://localhost", {
    body: input.value,
    method: "POST",
  });
  console.log(response);
  output.textContent = await response.text();
});
window.addEventListener("message", (event) => {
  console.log(event);
});
