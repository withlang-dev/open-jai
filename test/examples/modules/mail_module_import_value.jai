#import "Basic";

#run {
    Mail :: #import "Mail";

    smtp: Mail.Mail_Server;
    smtp.host = "smtp.example.test";
    smtp.port = "587";
    smtp.enable_ssl = true;
    smtp.username = "user";
    smtp.password = "password";

    message: Mail.Mail_Message;
    message.from = "from@example.test";
    array_add(*message.to, "to@example.test");
    message.subject = "Subject";
    message.body = "Body";
    message.html = false;

    print("mail:% %\n", smtp.enable_ssl, Mail.mail_send(smtp, message));
}

main :: () {}
