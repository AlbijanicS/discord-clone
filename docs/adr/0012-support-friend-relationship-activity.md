# Support Friend relationship activity

The Activity Feed includes incoming Friend Requests and accepted-request events in addition to Message-backed activity. Activity Items therefore support either a Message source or a Friend relationship source under kind-specific constraints; friendship updates broadcast only on private recipient topics, declines remain silent, and cancelling a pending request removes its received-request Activity Item.
