"""
Script to send individualized email requests to Pennsylvania state parks and
forests near Philadelphia asking for permission to perform metal detecting.

This script uses Python's ``smtplib`` to connect to Gmail's SMTP server
and send a polite, customized message to each recipient.  Before running
the script you must do the following:

1. Create an app‑specific password for your Gmail account (Google no longer
   allows logging in via ``smtplib`` with your normal account password).  See
   https://support.google.com/accounts/answer/185833 for instructions.
2. Update the ``GMAIL_ADDRESS`` and ``GMAIL_APP_PASSWORD`` variables below
   with your personal Gmail address and the app‑specific password you
   generated.  Keep these credentials private and never commit them to
   version control.
3. Verify that the list of parks and forests is correct and up‑to‑date.  The
   script currently includes parks and forests within roughly a two‑hour drive
   of Philadelphia.  If you wish to add or remove recipients, edit the
   ``RECIPIENTS`` list accordingly.

Running the script will iterate through all entries in ``RECIPIENTS`` and
send a separate email to each address.  The subject line and body of the
email are tailored using the park or forest name.  The message states that
you are a member of the Philadelphia historical society, have taken
archaeology classes at the University of Rochester, and wish to obtain
permission to metal detect on areas of the property not in use by other
visitors.  It also reassures the recipient that you will report any
interesting finds in accordance with regulations.

Note: This script only sends the emails—it does not automatically handle
replies.  You should monitor your Gmail inbox for responses from the
parks and forests.  Use discretion when following up on any permission
granted and be sure to adhere to all state and local laws.
"""

import smtplib
import time
from email.message import EmailMessage


# -----------------------------------------------------------------------------
# User configuration
# -----------------------------------------------------------------------------
# Replace the values below with your Gmail address and the app‑specific
# password you created for this script.  Do NOT store your normal Gmail
# password here; use an app password instead.  See the module docstring for
# details.
GMAIL_ADDRESS = "otcaseko@gmail.com"
GMAIL_APP_PASSWORD = "mvdz nxlm hitj pgek"


def build_recipients():
    """Return a list of recipient dictionaries.

    Each dictionary contains the keys ``name`` and ``email``.  The ``name``
    corresponds to the park or forest name and is used to personalize the
    greeting.  The ``email`` should be the official contact address for that
    park or forest.
    """
    return [
        {"name": "Benjamin Rush State Park", "email": "neshaminysp@pa.gov"},
        {"name": "Evansburg State Park", "email": "evansburgsp@pa.gov"},
        {"name": "Fort Washington State Park", "email": "fortwashingtonsp@pa.gov"},
        {"name": "Ridley Creek State Park", "email": "ridleycreeksp@pa.gov"},
        {"name": "Neshaminy State Park", "email": "neshaminysp@pa.gov"},
        {"name": "Marsh Creek State Park", "email": "marshcreeksp@pa.gov"},
        {"name": "Tyler State Park", "email": "tylersp@pa.gov"},
        {"name": "Nockamixon State Park", "email": "nockamixonsp@pa.gov"},
        {"name": "Susquehannock State Park", "email": "SusquehannockStatePark@pa.gov"},
        {"name": "Swatara State Park", "email": "memorialsp@pa.gov"},
        {"name": "Gifford Pinchot State Park", "email": "giffordpinchotsp@pa.gov"},
        {"name": "French Creek State Park", "email": "frenchcreeksp@pa.gov"},
        {"name": "Washington Crossing Historic Park", "email": "washingtoncrossingsp@pa.gov"},
        {"name": "Ralph Stover State Park", "email": "delawarecanalsp@pa.gov"},
        {"name": "Norristown Farm Park", "email": "parkregion4sp@pa.gov"},
        {"name": "Beltzville State Park", "email": "beltzvillesp@pa.gov"},
        {"name": "Locust Lake State Park", "email": "tuscarorasp@pa.gov"},
        {"name": "Tuscarora State Park", "email": "tuscarorasp@pa.gov"},
        {"name": "Hickory Run State Park", "email": "hickoryrunsp@pa.gov"},
        {"name": "Codorus State Park", "email": "codorussp@pa.gov"},
        {"name": "Jacobsburg Environmental Education Center", "email": "jacobsburgsp@pa.gov"},
        {"name": "Lehigh Gorge State Park", "email": "hickoryrunsp@pa.gov"},
        {"name": "Memorial Lake State Park", "email": "memorialsp@pa.gov"},
        {"name": "William Penn State Forest", "email": "FD17@pa.gov"},
        {"name": "Weiser State Forest", "email": "fd18@pa.gov"},
    ]


def compose_email(to_address: str, park_name: str) -> EmailMessage:
    """Create an ``EmailMessage`` object for a given recipient.

    Parameters
    ----------
    to_address : str
        The email address of the park or forest to contact.
    park_name : str
        The name of the park or forest.  Used to personalize the greeting and
        subject line.

    Returns
    -------
    EmailMessage
        A fully populated email message ready to be sent via SMTP.
    """
    msg = EmailMessage()
    msg["From"] = GMAIL_ADDRESS
    msg["To"] = to_address
    msg["Subject"] = f"Metal detecting permission request for {park_name}"

    # Body of the email.  Adjust the wording here if you wish to include
    # additional details.  Keep the tone polite and respectful.
    body = f"""
Dear {park_name} staff,

I hope this message finds you well. I am a member of the Philadelphia Historical Society and have completed archaeology courses at the University of Rochester. I am writing to inquire about the possibility of obtaining permission to conduct metal detecting at {park_name}.

My goal is to explore areas of the park or forest that are not being used by other visitors. I will, of course, follow all applicable laws and guidelines and will avoid any sensitive or restricted areas. Should I discover any historically or culturally significant items, I will promptly report them to the appropriate authorities and the park office.

Thank you for considering my request. I would appreciate any information you can provide about the permitting process or any restrictions that apply to metal detecting within your jurisdiction. I look forward to the opportunity to work cooperatively with your staff to ensure that all activities are conducted responsibly.

Sincerely,

Oliver Otcasek
"""
    msg.set_content(body)
    return msg


def send_emails():
    """Send emails to all recipients defined in ``build_recipients()``.

    This function establishes an encrypted connection to Gmail's SMTP server,
    logs in with the provided credentials, sends each message, and then
    closes the connection.  If an error occurs during sending, it prints
    a message but continues to the next recipient.
    """
    recipients = build_recipients()
    if not recipients:
        print("No recipients defined. Exiting.")
        return

    # Connect to Gmail's SMTP server using SSL.  Port 465 is the default for
    # SMTP over SSL.
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
        try:
            smtp.login(GMAIL_ADDRESS, GMAIL_APP_PASSWORD)
        except smtplib.SMTPAuthenticationError as exc:
            print("Failed to authenticate with Gmail. Please check your email "
                  "address and app‑specific password.")
            raise exc

        for recipient in recipients:
            to_addr = recipient["email"]
            park_name = recipient["name"]
            msg = compose_email(to_addr, park_name)
            try:
                smtp.send_message(msg)
                print(f"Email sent to {park_name} <{to_addr}>")
                time.sleep(10)
            except Exception as exc:
                print(f"Failed to send email to {park_name} <{to_addr}>: {exc}")


if __name__ == "__main__":
    send_emails()