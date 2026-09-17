# Supplier SMS templates

**Owned by Person Two.** The copy and the parser are one artefact: they change
together, in one pull request, with the regression fixtures updated.

Every template is under 320 characters, states who is texting, what is wanted,
and how to stop. Reply handling is a grammar, not a language model — see the
parser cases at the bottom.

## outreach.v1

```
PLUG: New request near you.
Service: {service}
Budget: under ${budget}
Time: {window}
Distance: {distance} mi

Reply YES <price> <time> to offer, or NO.
Reply STOP to never receive these.
```

## confirmation.v1

```
PLUG: Got it. We sent your offer (${price} at {time}) to the customer.
You'll get a text if they book.
```

## booked.v1

```
PLUG: Booked. {customer_first_name} is coming at {time} for {service} at ${price}.
Reply HELP for support.
```

## help.v1

```
PLUG connects nearby customers to you by text. Reply YES <price> <time> to an
offer, or NO to skip. Reply PAUSE to stop for 24h, STOP to opt out completely.
Support: support@plug.app
```

## stop-confirm.v1

```
PLUG: You're opted out. You will not receive further requests.
Reply START to opt back in.
```

## Parser cases — the regression fixtures

| Reply | Parses as | Price | Time |
|---|---|---|---|
| `YES 30 2:15` | accept | 3000 | 14:15 |
| `yes 30 2:15pm` | accept | 3000 | 14:15 |
| `Y 28 2:30 PM` | accept | 2800 | 14:30 |
| `YES` | accept | — | — |
| `NO` | decline | — | — |
| `no thanks` | decline | — | — |
| `STOP` / `stop` / `UNSUBSCRIBE` | stop | — | — |
| `PAUSE` | pause | — | — |
| `HELP` | help | — | — |
| `maybe later?` | **unparseable** | — | — |
| `yes but 45 min` | **unparseable** | — | — |
| emoji only | **unparseable** | — | — |
| empty | **unparseable** | — | — |

An unparseable reply creates **no offer** and applies **no supplier penalty**.
An ambiguous reply must never become a real offer with a real price.
