/* ---- PARAMS ---- */
CREATE TABLE staking_params
(
    bond_denom TEXT NOT NULL
);

/* ---- POOL ---- */

CREATE TABLE staking_pool
(
    height            BIGINT NOT NULL UNIQUE PRIMARY KEY,
    bonded_tokens     BIGINT NOT NULL,
    not_bonded_tokens BIGINT NOT NULL
);
CREATE INDEX staking_pool_height_index ON staking_pool (height);

/* ---- VALIDATORS INFO ---- */

CREATE TABLE validator_info
(
    consensus_address     TEXT NOT NULL UNIQUE PRIMARY KEY REFERENCES validator (consensus_address),
    operator_address      TEXT NOT NULL UNIQUE,
    self_delegate_address TEXT REFERENCES account (address),
    max_change_rate       TEXT NOT NULL,
    max_rate              TEXT NOT NULL
);
CREATE INDEX validator_info_operator_address_index ON validator_info (operator_address);

CREATE TABLE validator_description
(
    validator_address TEXT NOT NULL REFERENCES validator (consensus_address),
    moniker           TEXT,
    identity          TEXT,
    website           TEXT,
    security_contact  TEXT,
    details           TEXT,
    height            BIGINT,
    PRIMARY KEY (validator_address, height)
);
CREATE INDEX validator_description_validator_address_index ON validator_description (validator_address);
CREATE INDEX validator_description_height_index ON validator_description (height);

CREATE TABLE validator_commission
(
    validator_address   TEXT    NOT NULL REFERENCES validator (consensus_address),
    commission          DECIMAL NOT NULL,
    min_self_delegation BIGINT  NOT NULL,
    height              BIGINT  NOT NULL,
    PRIMARY KEY (validator_address, height)
);
CREATE INDEX validator_commission_validator_address_index ON validator_commission (validator_address);
CREATE INDEX validator_commission_height_index ON validator_commission (height);

CREATE TABLE validator_voting_power
(
    validator_address TEXT   NOT NULL REFERENCES validator (consensus_address),
    voting_power      BIGINT NOT NULL,
    height            BIGINT NOT NULL REFERENCES block (height),
    PRIMARY KEY (validator_address, height)
);
CREATE INDEX validator_voting_power_validator_address_index ON validator_voting_power (validator_address);
CREATE INDEX validator_voting_power_height_index ON validator_voting_power (height);

CREATE TABLE validator_status
(
    validator_address TEXT    NOT NULL REFERENCES validator (consensus_address),
    status            INT     NOT NULL,
    jailed            BOOLEAN NOT NULL,
    height            BIGINT,
    PRIMARY KEY (validator_address, height)
);
CREATE INDEX validator_status_validator_address_index ON validator_status (validator_address);
CREATE INDEX validator_status_height_index ON validator_status (height);

/* ---- DELEGATIONS ---- */

/*
 * This table holds the HISTORICAL delegations.
 * It should be updated on a MESSAGE basis, to avoid data duplication.
 */
CREATE TABLE delegation
(
    /* This is used to make it possible for Hasura to connect validator and self_delegations properly */
    id                SERIAL PRIMARY KEY NOT NULL,

    validator_address TEXT               NOT NULL REFERENCES validator (consensus_address),
    delegator_address TEXT               NOT NULL REFERENCES account (address),
    amount            COIN               NOT NULL,
    shares            NUMERIC            NOT NUll,
    height            BIGINT             NOT NULL
);
CREATE INDEX delegation_validator_address_index ON delegation (validator_address);
CREATE INDEX delegation_delegator_address ON delegation (delegator_address);
CREATE INDEX delegation_height_index ON delegation (height);

/**
  * This function is used to add a self_delegations field to the validator table allowing to easily get all the
  * self delegations related to a specific validator.
 */
CREATE FUNCTION self_delegations(validator_row validator) RETURNS SETOF delegation AS
$$
SELECT *
FROM delegation
WHERE delegator_address = (
    SELECT self_delegate_address
    FROM validator_info
    WHERE validator_info.consensus_address = validator_row.consensus_address
)
$$ LANGUAGE sql STABLE;

/**
  * This function is used to have a Hasura compute field (https://hasura.io/docs/1.0/graphql/core/schema/computed-fields.html)
  * inside the delegation_history table, so that it's easy to determine whether an entry represents a self delegation or not.
 */
CREATE FUNCTION is_delegation_self_delegate(delegation_row delegation) RETURNS BOOLEAN AS
$$
SELECT (
           SELECT self_delegate_address
           FROM validator_info
           WHERE validator_info.consensus_address = delegation_row.validator_address
       ) = delegation_row.delegator_address
$$ LANGUAGE sql STABLE;

/*
 * This table holds the HISTORICAL unbonding delegations.
 * It should be updated on a MESSAGE basis, to avoid data duplication.
 */
CREATE TABLE unbonding_delegation
(
    validator_address    TEXT                        NOT NULL REFERENCES validator (consensus_address),
    delegator_address    TEXT                        NOT NULL REFERENCES account (address),
    amount               COIN                        NOT NUll,
    completion_timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    height               BIGINT                      NOT NULL
);
CREATE INDEX unbonding_delegation_validator_address_index ON unbonding_delegation (validator_address);
CREATE INDEX unbonding_delegation_delegator_address_index ON unbonding_delegation (delegator_address);
CREATE INDEX unbonding_delegation_height_index ON unbonding_delegation (height);

/*
 * This table holds the HISTORICAL redelegations.
 * It should be updated on a MESSAGE basis, to avoid data duplication.
 */
CREATE TABLE redelegation
(
    delegator_address     TEXT                        NOT NULL REFERENCES account (address),
    src_validator_address TEXT                        NOT NULL REFERENCES validator (consensus_address),
    dst_validator_address TEXT                        NOT NULL REFERENCES validator (consensus_address),
    amount                COIN                        NOT NULL,
    completion_time       TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    height                BIGINT                      NOT NULL
);
CREATE INDEX redelegation_delegator_address_index ON redelegation (delegator_address);
CREATE INDEX redelegation_src_validator_address_index ON redelegation (src_validator_address);
CREATE INDEX redelegation_dst_validator_address_index ON redelegation (dst_validator_address);
CREATE INDEX redelegation_height_index ON redelegation (height);

/*--------------------------------------------*/

/*
 * This holds the votes that is the evidence of a double sign.
 * It should be updated on a BLOCK basis when a double sign occurs.
 */
CREATE TABLE double_sign_vote
(
    id                SERIAL PRIMARY KEY,
    type              SMALLINT NOT NULL,
    height            BIGINT   NOT NULL,
    round             INT      NOT NULL,
    block_id          TEXT     NOT NULL,
    validator_address TEXT     NOT NULL REFERENCES validator (consensus_address),
    validator_index   INT      NOT NULL,
    signature         TEXT     NOT NULL,
    UNIQUE (block_id, validator_address)
);
CREATE INDEX double_sign_vote_validator_address_index ON double_sign_vote (validator_address);
CREATE INDEX double_sign_vote_height_index ON double_sign_vote (height);

/*
 * This holds the double sign evidences.
 * It should be updated on a on BLOCK basis.
 */
CREATE TABLE double_sign_evidence
(
    height    BIGINT NOT NULL,
    vote_a_id BIGINT NOT NULL REFERENCES double_sign_vote (id),
    vote_b_id BIGINT NOT NULL REFERENCES double_sign_vote (id)
);
CREATE INDEX double_sign_evidence_height_index ON double_sign_evidence (height);