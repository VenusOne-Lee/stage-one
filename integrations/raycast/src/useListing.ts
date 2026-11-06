import { useEffect, useState } from "react";
import { list, Listing } from "./stage";

export function useListing() {
  const [data, setData] = useState<Listing>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    list()
      .then(setData)
      .catch((e: Error) => setError(e.message));
  }, []);
  return { data, error, isLoading: !data && !error };
}
