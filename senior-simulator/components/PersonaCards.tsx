"use client";

import type { Persona, Profile } from "@/lib/types";
import { currency } from "@/lib/formatters";

interface Props {
  personas: Persona[];
  onSelect: (profile: Partial<Profile>) => void;
  selectedId?: string;
}

export default function PersonaCards({ personas, onSelect, selectedId }: Props) {
  return (
    <div className="space-y-3">
      <h3 className="text-lg font-semibold text-white">Preset Scenarios</h3>
      <p className="text-sm text-gray-400">
        Click to load a scenario. See how different Canadians interact with the benefit system.
      </p>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {personas.map((persona) => (
          <button
            key={persona.id}
            onClick={() => onSelect(persona.profile)}
            className={`text-left p-4 rounded-lg border transition-all ${
              selectedId === persona.id
                ? "border-amber-500 bg-amber-900/20"
                : "border-gray-700 bg-gray-800/50 hover:border-gray-500"
            }`}
          >
            <h4 className="font-semibold text-white text-sm">{persona.name}</h4>
            <p className="text-xs text-gray-400 mt-1">{persona.description}</p>
            {persona.result && (
              <div className="mt-3 flex gap-3 text-xs">
                <div>
                  <span className="text-gray-500">Benefits:</span>{" "}
                  <span className="text-green-400 font-mono">{currency(persona.result.total_benefits)}</span>
                </div>
                <div>
                  <span className="text-gray-500">Net:</span>{" "}
                  <span className="text-amber-400 font-mono">{currency(persona.result.net_income)}</span>
                </div>
              </div>
            )}
            <p className="text-xs text-red-400/80 mt-2 italic">{persona.gaming_explanation}</p>
          </button>
        ))}
      </div>
    </div>
  );
}
