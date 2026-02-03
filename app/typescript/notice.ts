export default class Notice {
    public static init() {
        document.querySelector("#close-notice-link").addEventListener("click", (event) => {
            event.preventDefault();
            document.querySelector("#notice").style.display = "none";
        });
    }
}
