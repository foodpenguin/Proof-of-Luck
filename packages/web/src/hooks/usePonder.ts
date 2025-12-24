import { useQuery, UseQueryOptions } from '@tanstack/react-query';
import { ponderClient } from '../utils/ponder';

export function usePonderQuery<T>(key: string[], query: string, variables?: any, options?: Omit<UseQueryOptions<T>, 'queryKey' | 'queryFn'>) {
  return useQuery<T>({
    queryKey: key,
    queryFn: async () => {
      return await ponderClient.request<T>(query, variables);
    },
    refetchInterval: 5000, // Poll every 5 seconds for real-time-ish updates
    ...options
  });
}
