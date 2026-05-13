#scope_export;

Mail_Server :: struct {
    host: string;
    port: string;
    enable_ssl: bool;
    username: string;
    password: string;
}

Mail_Message :: struct {
    from: string;
    to: [..] string;
    subject: string;
    body: string;
    html: bool;
}

mail_send :: (server: Mail_Server, message: Mail_Message) -> bool {
    return false;
}
