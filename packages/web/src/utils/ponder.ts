import { GraphQLClient } from 'graphql-request';

const PONDER_URL = process.env.NEXT_PUBLIC_PONDER_URL || 'http://localhost:42069';

export const ponderClient = new GraphQLClient(PONDER_URL);

export const gql = (strings: TemplateStringsArray, ...values: any[]) => {
  return String.raw({ raw: strings }, ...values);
};
